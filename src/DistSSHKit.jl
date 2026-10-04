"""
DistSSHKit — meta-package for one run and the queue.

Users add this package. DistSSHRun is one run. DistSSHQueue is the queue.
This module reexports their public names and keeps `julia -m DistSSHKit`.
"""
module DistSSHKit

using DistSSHQueue
using DistSSHRun
import DistSSHUp

# Names this module defines itself. Do not import them from a dependency.
const _OWN = (
    :dist_ssh_kit_version,
    :main,
    :print_kit_root_usage,
    :println_kit_version,
)

"""Import `n` from `mod`. `export_name` reexports it."""
function _bind!(mod::Module, n::Symbol; export_name::Bool)
    Core.eval(
        @__MODULE__,
        Expr(:import, Expr(:(:), Expr(:., nameof(mod)), Expr(:., n))),
    )
    export_name || return nothing
    Core.eval(@__MODULE__, Expr(:export, n))
    return nothing
end

const _FROM = Dict{Symbol, Module}()

"""Reexport names `mod` already exports. Private names stay there."""
function _adopt!(mod::Module)
    for n in names(mod)
        n === nameof(mod) && continue
        n in _OWN && continue
        if haskey(_FROM, n)
            _FROM[n] === mod && continue
            error("DistSSHKit cannot take `$n` from both $(nameof(mod)) and $(nameof(_FROM[n]))")
        end
        _bind!(mod, n; export_name = true)
        _FROM[n] = mod
    end
    return nothing
end

_adopt!(DistSSHRun)
_adopt!(DistSSHQueue)

# Qualified names this repo's demos and SSH checks still call. Not exported.
const _QUALIFIED = (
    :KIT_PROGRESS,
    :KIT_PROGRESS_SUSPEND,
    :KitCliSession,
    :KitProgressState,
    :apply_kit_cli_session!,
    :clear_detect_julia_path_cache!,
    :close_log_file,
    :find_local_juliaup,
    :get_local_git_hash,
    :get_remote_julia_version,
    :kit_job_mark_comment,
    :kit_job_pkill_pattern,
    :kit_progress_done!,
    :kit_progress_latest,
    :kit_verbosity,
    :parse_julia_version,
    :resolve_distributed_output_dir!,
    :resolve_remote_julia,
    :set_kit_verbosity!,
    :setup_cli_host_token,
)

for _n in _QUALIFIED
    isdefined(@__MODULE__, _n) && continue
    _bind!(DistSSHRun, _n; export_name = false)
end

# Channel names live on DistSSHUp. Not exported.
const _QUALIFIED_UP = (
    :julia_version_mismatch_kind,
    :juliaup_channel,
)

for _n in _QUALIFIED_UP
    isdefined(@__MODULE__, _n) && continue
    _bind!(DistSSHUp, _n; export_name = false)
end

function _project_version()::VersionNumber
    path = joinpath(pkgdir(@__MODULE__), "Project.toml")
    for line in eachline(path)
        m = match(r"^version\s*=\s*\"([^\"]+)\"", line)
        m === nothing || return VersionNumber(m.captures[1])
    end
    return v"0.0.0"
end

"""Version of this meta-package, from its `Project.toml`."""
dist_ssh_kit_version()::VersionNumber = _project_version()

"""
    println_kit_version(io::IO=stdout)

Print `DistSSHKit` and this package's version.
"""
function println_kit_version(io::IO = stdout)
    println(io, "DistSSHKit $(dist_ssh_kit_version())")
    return nothing
end

export println_kit_version

const _RUN_COMMANDS = (
    "demo",
    "drive",
    "go",
    "plan",
    "pool",
    "progress",
    "ride",
    "setup",
    "size",
    "up",
)
const _QUEUE_ONLY = (
    "add-host",
    "cancel",
    "disable",
    "enable",
    "fetch",
    "list-host",
    "remove-host",
    "serve",
    "service",
    "status",
    "stop",
    "submit",
    "teardown",
    "watch",
)
const _QUEUE_HELP_TOPICS = ("client", "qhost", "queue", "queue-host")

"""Top-level `julia -m DistSSHKit` usage (no subcommand)."""
function print_kit_root_usage(io::IO = stderr)
    DistSSHRun.print_help_chrome(string(DistSSHRun.cli_entry()); io = io)
    DistSSHRun.print_help_section("Usage"; io = io)
    DistSSHRun.print_help_lines(io, "  $(DistSSHRun.cli_m()) <command> [args...]")
    DistSSHRun.print_help_blank(io)
    DistSSHRun.print_help_section("Run"; io = io)
    DistSSHRun.print_help_lines(
        io,
        "  setup              Clone / sync / check remotes",
        "  up                 Align a Julia channel with juliaup",
        "  go                 Run an as-is complete job",
        "  ride               Experimental auto-split of map / filter",
        "  drive              Distributed workers + collect",
        "  plan               Inspect a script; do not run",
        "  size               Estimate worker counts",
        "  pool               Cluster cores / health (no job)",
        "  demo               Install or list example scripts",
        "  progress           Phase seconds from kit.progress",
    )
    DistSSHRun.print_help_blank(io)
    DistSSHRun.print_help_section("Client"; io = io)
    DistSSHRun.print_help_lines(
        io,
        "  submit             Enqueue go / ride / drive",
        "  status             Snapshot of the store",
        "  watch              Live status",
        "  cancel             Drop queued or stop running",
        "  fetch              Copy a finished leaf",
        "  list-host          Inventory",
        "  stop               Stop serve, keep files",
        "  teardown           Stop serve and remove ~/.distsshqueue",
        "  qhost:HOST         SSH that client command to the queue host",
    )
    DistSSHRun.print_help_blank(io)
    DistSSHRun.print_help_section("Queue host"; io = io)
    DistSSHRun.print_help_lines(
        io,
        "  qhost setup        Write config.toml if missing",
        "  qhost up           Align config hosts with juliaup",
        "  qhost add-host     Add host tokens",
        "  qhost remove-host  Drop host tokens",
        "  qhost serve        Run serve in this terminal",
        "  qhost enable       Start serve after reboot",
        "  qhost disable      Remove that OS registration",
        "  qhost service      Queue host service",
        "  qhost size         size / plan / pool on the queue host",
    )
    DistSSHRun.print_help_blank(io)
    DistSSHRun.print_help_section("Examples"; io = io)
    DistSSHRun.print_help_lines(
        io,
        "  $(DistSSHRun.cli_m_project()) setup --check child:host1",
        "  $(DistSSHRun.cli_m_project()) up child:host1",
        "  $(DistSSHRun.cli_m_project()) go SCRIPT.jl",
        "  $(DistSSHRun.cli_m_project()) ride parent:2 SCRIPT.jl",
        "  $(DistSSHRun.cli_m_project()) drive parent:2 SCRIPT.jl",
        "  $(DistSSHRun.cli_m_project()) plan SCRIPT.jl",
        "  $(DistSSHRun.cli_m_project()) qhost:HOST submit drive parent:4 SCRIPT.jl",
        "  $(DistSSHRun.cli_m_project()) qhost setup",
        "  $(DistSSHRun.cli_m_project()) qhost up",
    )
    DistSSHRun.print_help_blank(io)
    println(io, "Run `$(DistSSHRun.cli_m()) <command> -h` for flags.")
    return nothing
end

function _leading_command(args::Vector{String})
    saw = false
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--remote-julia" && i < length(args)
            saw = true
            i += 2
        elseif a == "--queue-env" && i < length(args)
            saw = true
            i += 2
        elseif startswith(a, "qhost:")
            saw = true
            i += 1
        elseif a == "--qhost" || a == "--project" || startswith(a, "--project=")
            saw = true
            break
        else
            break
        end
    end
    sub = i <= length(args) ? String(args[i]) : ""
    if !saw && length(args) >= 2 && startswith(args[2], "qhost:")
        saw = true
        sub = String(args[1])
    end
    return sub, saw
end

"""Drop a leading `qhost` group word. `qhost:HOST` is a client hop and stays."""
function _without_qhost_group(args::Vector{String})::Union{Nothing, Vector{String}}
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--remote-julia" && i < length(args)
            i += 2
        elseif a == "--queue-env" && i < length(args)
            i += 2
        elseif startswith(a, "qhost:")
            return nothing
        else
            break
        end
    end
    i <= length(args) || return nothing
    String(args[i]) == "qhost" || return nothing
    return [args[1:(i - 1)]; args[(i + 1):end]]
end

function _version_flag(arg::AbstractString)::Bool
    return arg in ("--version", "-v", "-V")
end

"""
    main(args::Vector{String}=copy(ARGS))

CLI entry. Prefer Julia 1.13+ and `julia -m DistSSHKit SUBCOMMAND …`.

Run commands (`setup`, `up`, `go`, `ride`, `drive`, `plan`, `size`, `pool`,
`demo`, `progress`) stay the run surface. Client commands take an optional
`qhost:HOST`. Queue-host commands start with `qhost` (`qhost setup`,
`qhost up`, `qhost serve`, `qhost size`).
"""
function main(args::Vector{String} = copy(ARGS))::Cint
    return DistSSHRun.with_cli_entry(:DistSSHKit) do
        _main(args)
    end
end

function _main(args::Vector{String})::Cint
    if length(args) == 1 && _version_flag(args[1])
        println_kit_version()
        return 0
    end
    if length(args) == 2 && args[1] in ("-h", "--help", "help") &&
            args[2] in _QUEUE_HELP_TOPICS
        return DistSSHQueue.main(args)
    end
    if length(args) == 1 && args[1] in ("-h", "--help", "help")
        print_kit_root_usage()
        return 0
    end
    if isempty(args)
        print_kit_root_usage()
        return 1
    end
    stripped = _without_qhost_group(args)
    if stripped !== nothing
        return DistSSHQueue.main(stripped)
    end
    sub, saw_queue = _leading_command(args)
    if saw_queue || sub in _QUEUE_ONLY
        return DistSSHQueue.main(args)
    end
    if sub in _RUN_COMMANDS
        rest = args[2:end]
        if length(rest) == 1 && _version_flag(rest[1])
            println_kit_version()
            return 0
        end
        return DistSSHRun.main(args)
    end
    if any(endswith(String(a), ".jl") for a in args)
        DistSSHRun.print_cli_error(
            "No command (got $(repr(sub))). Kit does not infer go / ride / drive.",
        )
        println(stderr, "  go SCRIPT.jl      as-is complete job (timing without rewrite)")
        println(stderr, "  ride … SCRIPT.jl  experimental map / filter")
        println(stderr, "  drive … SCRIPT.jl Distributed")
        println(stderr, "  plan SCRIPT.jl    inspect; do not run")
    else
        DistSSHRun.print_cli_error("Unknown subcommand: $sub")
        println(
            stderr,
            "Expected: setup | up | go | ride | drive | plan | size | pool | demo | progress",
        )
        println(
            stderr,
            "Queue: submit | status | watch | cancel | fetch | list-host | add-host | remove-host | serve | stop | enable | disable | service | teardown",
        )
    end
    println(stderr)
    print_kit_root_usage()
    return 1
end

Base.eval(@__MODULE__, :(@main))

end # module DistSSHKit
