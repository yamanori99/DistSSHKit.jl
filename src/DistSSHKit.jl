"""
DistSSHKit — local + SSH Julia runs (`go` / `drive` / `setup`) and a small API
(`go!`, `drive!`, `pipeline!`, …).

Package entry: exports, version, `include`s, `main` (`@main` on Julia 1.12+).
CLI entries live under `src/cli/`; argv parsers under `src/DistSSHKit/argv/`.
"""
module DistSSHKit

using Dates
using Distributed
using Pkg
using TOML

# Public surface for application / driver authors.
# Prefer `julia -m DistSSHKit …` for day-to-day CLI.
#   go! / drive! / sync! / instantiate! / collect! / size! — steps
#   setup! — Julian mirror of `setup --delete|--rsync|…`
#   pipeline! — optional sugar (sync → size! → drive → collect)
#   execute! — one seam over go!/drive!; detached=true returns KitProcess
#   worker tokens — parse/classify host:N grammar and build WorkerPlan
#   go / drive — argv wrappers (not exported; tests / `main`)
#   queue CLI surface — parsers, SSH resolve, paths, help chrome
#   worker_pmap — world-age escape hatch inside drivers
export worker_pmap
export KitSession
export HostResult
export SyncResult
export WorkerPlan
export parse_worker_tokens
export ParsedWorkerTokens
export worker_tokens_fully_specified
export child_hosts_from_tokens
export worker_plan_from_tokens
export split_worker_token
export host_tokens
export is_parent_host_name
export DriveResult
export HostRunResult
export DriveHostStatus
export CollectResult
export KitRunResult
export KitProcess
export kit_run_result
export PipelineConfig
export PipelineResult
export sync!
export instantiate!
export setup!
export size!
export drive!
export collect!
export pipeline!
export pipeline_config_from_env
export report_pipeline_errors
export report_run_errors
export go!
export GoResult
export report_go_errors
export execute!
export allocate_output_dir
export execute_detached_accepts
export execute_kwargs_from_parsed
export kit_pid_alive
export kit_pid_file_running
export terminate!
export terminate_run!
export kit_result_from_dir
export drive_host_status
export parse_progress_line
export kit_progress_latest
export kit_progress_phases
export parse_go_args
export parse_drive_args
export show_go_usage
export show_drive_usage
export println_kit_version
export ssh_opts
export resolve_remote_julia
export run_on_host
export resolve_controller_julia
export canonical_local_path
export short_path
export resolve_pkg_project_dir
export explain_script_not_found
export print_cli_error
export print_help_chrome
export print_help_section
export print_help_lines
export print_help_blank
export print_colored
export SPINNER_FRAMES
# `go` / `drive` argv wrappers stay unexported (`main` and tests).
# `_print_colored` remains an alias of `print_colored`.


# Implementation

include("DistSSHKit/display.jl")
include("DistSSHKit/explain.jl")
include("DistSSHKit/argv/args.jl")
include("DistSSHKit/argv/session.jl")
include("DistSSHKit/hosts.jl")
include("DistSSHKit/remote.jl")
include("DistSSHKit/demos.jl")
include("DistSSHKit/distributed.jl")
include("DistSSHKit/drive/types.jl")
include("DistSSHKit/size/measure.jl")
include("DistSSHKit/setup.jl")
include("DistSSHKit/argv/drive_args.jl")
include("DistSSHKit/argv/go_args.jl")
include("DistSSHKit/argv/setup_args.jl")
include("DistSSHKit/argv/size_args.jl")
include("DistSSHKit/drive.jl")
include("DistSSHKit/drive/runtime/heartbeat.jl")
include("DistSSHKit/argv/size_report.jl")
include("DistSSHKit/go.jl")
include("DistSSHKit/execute.jl")

const _KIT_ROOT = dirname(@__DIR__)

# Kit version (from Project.toml).
# `@__DIR__` is `src/` — keep path resolution here, not in included files.

"""Read `version` from `path` (`Project.toml`); return `nothing` if missing or invalid."""
function _project_toml_version(path::AbstractString)::Union{Nothing,VersionNumber}
    p = String(path)
    isfile(p) || return nothing
    try
        raw = get(TOML.parsefile(p), "version", nothing)
        raw isa AbstractString || return nothing
        return VersionNumber(String(raw))
    catch
        return nothing
    end
end

const _DIST_SSH_KIT_PROJECT_TOML = joinpath(@__DIR__, "..", "Project.toml")

"""Semantic version of this vendored kit (from kit `Project.toml`)."""
const DIST_SSH_KIT_VERSION = something(
    _project_toml_version(_DIST_SSH_KIT_PROJECT_TOML),
    v"0.0.0",
)

dist_ssh_kit_version()::VersionNumber = DIST_SSH_KIT_VERSION

# CLI: load `src/cli/*.jl` into Main and run `*_main`.
#   julia --project=. -m DistSSHKit drive parent:2 script.jl

const _KIT_CLI_LOADED = Set{String}()
const _KIT_CLI_SCRIPTS = ("drive.jl", "go.jl", "setup.jl", "size.jl")

const _KIT_CLI_MAIN = Dict(
    "drive.jl" => :drive_main,
    "go.jl" => :go_main,
    "setup.jl" => :setup_main,
    "size.jl" => :size_main,
)

function _kit_cli_run_entry(script_base::String)::Cint
    sym = get(_KIT_CLI_MAIN, script_base, nothing)
    sym === nothing && return 0
    return Base.invokelatest() do
        result = getfield(Main, sym)()
        return result isa Cint ? result : 0
    end
end

function _append_script_arg_prelude!(args::Vector{String})
    raw = get(ENV, "DISTSSHKIT_SCRIPT_ARG_PRELUDE", "")
    isempty(raw) && return
    delete!(ENV, "DISTSSHKIT_SCRIPT_ARG_PRELUDE")
    for line in split(raw, '\n')
        s = strip(String(line))
        !isempty(s) && push!(args, s)
    end
end

function _merge_script_arg_prelude(rest::Vector{String})::Vector{String}
    merged = collect(String, rest)
    _append_script_arg_prelude!(merged)
    return merged
end

function _mark_kit_cli_subcommand_done!()
    ENV["DISTSSHKIT_CLI_SUBCOMMAND_DONE"] = "1"
end

function _consume_kit_cli_subcommand_done!()::Bool
    if get(ENV, "DISTSSHKIT_CLI_SUBCOMMAND_DONE", "") == "1"
        delete!(ENV, "DISTSSHKIT_CLI_SUBCOMMAND_DONE")
        return true
    end
    return false
end

"""Run a kit CLI script under `src/cli/` (`drive.jl`, `setup.jl`, …) with `ARGS` set."""
function _run_kit_cli_script(script_name::AbstractString, args::Vector{String})::Cint
    haskey(ENV, "DISTRIBUTED_PROJECT_ROOT") || (ENV["DISTRIBUTED_PROJECT_ROOT"] = pwd())
    # `args` may alias `ARGS` (the app launcher can pass `ARGS` directly).
    args_snapshot = collect(String, args)
    empty!(ARGS)
    append!(ARGS, args_snapshot)
    script_path::String = if isabspath(script_name)
        String(script_name)
    else
        joinpath(@__DIR__, "cli", String(script_name))
    end
    script_base = basename(script_path)
    prev_include = get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", nothing)
    ENV["DIST_SSH_KIT_CLI_INCLUDE"] = "1"
    try
        if script_base in _KIT_CLI_SCRIPTS
            if !(script_base in _KIT_CLI_LOADED)
                Core.include(Main, script_path)
                push!(_KIT_CLI_LOADED, script_base)
            end
            return _kit_cli_run_entry(script_base)
        end
        Core.include(Main, script_path)
        return 0
    finally
        if prev_include === nothing
            delete!(ENV, "DIST_SSH_KIT_CLI_INCLUDE")
        else
            ENV["DIST_SSH_KIT_CLI_INCLUDE"] = prev_include
        end
        _mark_kit_cli_subcommand_done!()
    end
end

"""
    drive(args::Vector{String}=copy(ARGS))

Run `drive.jl` with `args` (same as `julia -m DistSSHKit drive …`).
"""
drive(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("drive.jl", args)

"""
    go(args::Vector{String}=copy(ARGS))

Run `go.jl` with `args` (same as `julia -m DistSSHKit go …`).
"""
go(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("go.jl", args)

"""
    setup(args::Vector{String}=copy(ARGS))

Run `setup.jl` (clone / sync / cleanup) with `args` (same as `julia -m DistSSHKit setup …`).
"""
setup(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("setup.jl", args)

"""
    run_size(args::Vector{String}=copy(ARGS))

Run the `size` CLI (`size.jl`) with `args`. Named `run_size` so it does not
shadow `Base.size`. Prefer `julia -m DistSSHKit size …` day-to-day.
"""
run_size(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("size.jl", args)

"""
    main(args::Vector{String}=copy(ARGS))

CLI entry. Prefer Julia 1.12+ and `julia -m DistSSHKit SUBCOMMAND …`:

    julia --project=. -m DistSSHKit go SCRIPT.jl
    julia --project=. -m DistSSHKit drive parent:2 script.jl
    julia --project=. -m DistSSHKit setup --clone host1 host2
    julia --project=. -m DistSSHKit size parent child:host1
    julia --project=. -m DistSSHKit progress DIR

`main` remains for wrappers and tests; prefer `-m` day-to-day.
"""
function main(args::Vector{String}=copy(ARGS))::Cint
    known_subcommands = (
        "drive",
        "go",
        "demo",
        "setup",
        "size",
        "progress",
    )
    # Shorthand: hosts… SCRIPT.jl → go (as-is complete job)
    if length(args) >= 1 &&
       !(args[1] in known_subcommands) &&
       !(args[1] in ("--version", "-v", "-V", "-h", "--help", "help")) &&
       any(endswith(String(a), ".jl") for a in args)
        _mark_kit_cli_subcommand_done!()
        return go(collect(String, args))
    end
    if _consume_kit_cli_subcommand_done!()
        return 0
    end
    if length(args) == 1 && args[1] in ("--version", "-v", "-V")
        println_kit_version()
        return 0
    end
    if length(args) == 1 && args[1] in ("-h", "--help", "help")
        print_kit_root_usage()
        return 0
    end
    if isempty(args)
        print_kit_root_usage()
        return 1
    end
    subcommand, rest = args[1], args[2:end]
    if subcommand in ("drive", "go") &&
       any(endswith(String(a), ".jl") for a in rest)
        _mark_kit_cli_subcommand_done!()
    end
    if subcommand == "drive"
        return drive(_merge_script_arg_prelude(rest))
    elseif subcommand == "go"
        return go(_merge_script_arg_prelude(rest))
    elseif subcommand == "demo"
        return demo(rest)
    elseif subcommand == "setup"
        return setup(rest)
    elseif subcommand == "size"
        return run_size(rest)
    elseif subcommand == "progress"
        return progress(rest)
    else
        print_cli_error("Unknown subcommand: $subcommand")
        println(stderr, "Expected: go | drive | setup | size | demo | progress")
        println(stderr)
        print_kit_root_usage()
        return 1
    end
end

if VERSION >= v"1.12"
    Base.eval(@__MODULE__, :(@main))
end

end # module DistSSHKit
