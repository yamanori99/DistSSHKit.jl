"""
DistSSHKit — local + SSH Julia runs (`go` / `drive` / `setup`) and a small API
(`go!`, `drive!`, `pipeline!`, …).

Package entry: exports, version, `include`s, `(@main)` for `julia -m DistSSHKit …`.
CLI lives under `src/cli/`.
"""
module DistSSHKit

using Dates
using Distributed

# Public surface for application / driver authors.
# Prefer `julia -m DistSSHKit …` for day-to-day CLI.
#   go! / drive! / sync! / instantiate! / collect! / size! — steps
#   setup! — Julian mirror of `setup --delete|--rsync|…`
#   size_plan — same as size! (kept name)
#   pipeline! — optional sugar (sync → size! → drive → collect)
#   go / drive — same argv as the CLI (thin wrappers)
#   worker_pmap — world-age escape hatch inside drivers
export worker_pmap
export KitSession
export HostResult
export SyncResult
export WorkerPlan
export DriveResult
export CollectResult
export PipelineConfig
export PipelineResult
export sync!
export instantiate!
export setup!
export size_plan
export size!
export drive!
export collect!
export pipeline!
export pipeline_config_from_env
export report_pipeline_errors
export go!
export GoResult
export report_go_errors
export go
export drive


# Implementation

include("DistSSHKit/display.jl")
include("DistSSHKit/explain.jl")
include("DistSSHKit/cli/args.jl")
include("DistSSHKit/cli/session.jl")
include("DistSSHKit/hosts.jl")
include("DistSSHKit/remote.jl")
include("DistSSHKit/demos.jl")
include("DistSSHKit/distributed.jl")
include("DistSSHKit/drive/types.jl")
include("DistSSHKit/size/measure.jl")
include("DistSSHKit/setup.jl")
include("DistSSHKit/drive.jl")
include("DistSSHKit/go.jl")

const _KIT_ROOT = dirname(@__DIR__)

# Kit version (from Project.toml).
# `@__DIR__` is `src/` — keep path resolution here, not in included files.

"""Read `version = "x.y.z"` from `path` (`Project.toml`); return `nothing` if missing or invalid."""
function _project_toml_version(path::AbstractString)::Union{Nothing,VersionNumber}
    p = String(path)
    isfile(p) || return nothing
    try
        m = match(r"version\s*=\s*\"([^\"]+)\"", read(p, String))
        m === nothing && return nothing
        cap = m.captures[1]
        return cap isa AbstractString ? VersionNumber(String(cap)) : nothing
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
#   julia --project=. -m DistSSHKit drive local:2 script.jl

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

Run `setup.jl` (clone / sync / cleanup) with `args`. See [`drive`](@ref).
"""
setup(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("setup.jl", args)

"""
    run_size(args::Vector{String}=copy(ARGS))

Run the `size` CLI (`size.jl`) with `args`. Named `run_size` so it does not
shadow `Base.size`. Prefer `julia -m DistSSHKit size …` day-to-day.
"""
run_size(args::Vector{String}=copy(ARGS))::Cint = _run_kit_cli_script("size.jl", args)

"""
    (@main)(args::Vector{String}=copy(ARGS))

`julia -m DistSSHKit SUBCOMMAND …` (Julia 1.12+):

    julia --project=. -m DistSSHKit go SCRIPT.jl
    julia --project=. -m DistSSHKit drive local:2 script.jl
    julia --project=. -m DistSSHKit setup --clone host1 host2
    julia --project=. -m DistSSHKit size --local host1
"""
function (@main)(args::Vector{String}=copy(ARGS))::Cint
    known_subcommands = (
        "drive",
        "go",
        "demo",
        "setup",
        "size",
    )
    # Shorthand: hosts… SCRIPT.jl → go (as-is complete job)
    if length(args) >= 1 &&
       !(args[1] in known_subcommands) &&
       !(args[1] in ("--version", "-v", "-V")) &&
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
    else
        print_cli_error("Unknown subcommand: $subcommand")
        println(stderr, "Expected: go | drive | setup | size | demo")
        println(stderr)
        print_kit_root_usage()
        return 1
    end
end

end # module DistSSHKit
