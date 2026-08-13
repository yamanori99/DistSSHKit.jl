# Shared CLI session flags for drive / setup / size / go.

"""One-line meaning of `--require-git` (drive opt-in git parity)."""
const REQUIRE_GIT_MEANING = "opt-in git parity (off by default)"

"""Drive `--skip-git-guard`: compat no-op (parity already off)."""
const SKIP_GIT_GUARD_MEANING = "compat no-op (parity already off)"

"""Go `--skip-git-guard`: alias of `--skip-sync`."""
const GO_SKIP_GIT_GUARD_MEANING =
    "Same as --skip-sync (compat shared name with drive; default is already no pre-run sync)."

"""Shared collect-mode labels for help / docs."""
const COLLECT_MODE_HELP = """
Collect modes:
  post-run-new       drive after main(): files newer than run start (sentinel)
  collect-missing    drive --collect-missing / collect!(merge=false): absent locally
  collect-overwrite  drive --collect-overwrite / collect!(merge=true): merge remote tree
  slot-overwrite     go after each remote slot: rsync whole slot directory
"""

const KIT_QUIET_FLAG_HELP =
    "-q, --quiet         hide terminal detail"
const KIT_PROGRESS_FLAG_HELP =
    "--progress          live status (TTY default)"
const KIT_VERBOSE_FLAG_HELP =
    "--verbose           full detail (non-TTY default)"
const KIT_QUIET_ENV_HELP =
    "DISTSSHKIT_QUIET                  Same as --quiet"
const KIT_PROGRESS_ENV_HELP =
    "DISTSSHKIT_PROGRESS               Same as --progress"
const KIT_VERBOSE_ENV_HELP =
    "DISTSSHKIT_VERBOSE                Same as --verbose"

"""CLI default when no verbosity flag/env is set: live bar on a TTY, else verbose."""
kit_cli_auto_verbosity(; live::Union{Nothing,Bool}=nothing)::Symbol =
    something(live, kit_stdout_is_live()) ? :progress : :verbose

"""Read exclusive verbosity from env (`DISTSSHKIT_QUIET` / `_PROGRESS` / `_VERBOSE`)."""
function _env_verbosity()::Union{Nothing,Symbol}
    want_quiet = _env_flag("DISTSSHKIT_QUIET")
    want_progress = _env_flag("DISTSSHKIT_PROGRESS")
    want_verbose = _env_flag("DISTSSHKIT_VERBOSE")
    n = count(identity, (want_quiet, want_progress, want_verbose))
    n > 1 && throw(ArgumentError(
        "cannot combine DISTSSHKIT_QUIET, DISTSSHKIT_PROGRESS, and DISTSSHKIT_VERBOSE",
    ))
    want_quiet && return :quiet
    want_progress && return :progress
    want_verbose && return :verbose
    return nothing
end

"""Set exclusive sync mode (`:sync` / `:rsync` / `false`); throw if conflicting."""
function _kit_set_sync_mode!(
    current::Union{Nothing,Symbol,Bool},
    next::Union{Symbol,Bool};
    source::AbstractString="kit",
)
    if current !== nothing && current !== next
        msg = if source == "go"
            "$source: use only one of --sync / --rsync / --skip-sync / --skip-git-guard"
        else
            "$source: use only one of --sync / --rsync"
        end
        throw(ArgumentError(msg))
    end
    return next
end

"""Resolve verbosity; `quiet=true` maps to `:quiet`. Rejects quiet+progress/verbose."""
function _resolve_kit_verbosity(;
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
)::Symbol
    if verbosity !== nothing
        verbosity in (:verbose, :progress, :quiet) ||
            throw(ArgumentError("verbosity must be :verbose, :progress, or :quiet"))
        quiet && verbosity === :progress &&
            throw(ArgumentError("cannot combine --quiet (-q) with --progress"))
        quiet && verbosity === :verbose &&
            throw(ArgumentError("cannot combine --quiet (-q) with --verbose"))
        quiet && verbosity !== :quiet &&
            throw(ArgumentError("quiet=true conflicts with verbosity=$verbosity"))
        return quiet ? :quiet : verbosity
    end
    return quiet ? :quiet : kit_cli_auto_verbosity()
end

"""Runtime CLI session: verbosity, non-interactive mode, shared host list."""
mutable struct KitCliSession
    quiet::Bool
    verbosity::Symbol
    yes::Bool
    hosts_file::Union{Nothing,String}
    show_version::Bool
    hint_surface::Symbol
    verbosity_explicit::Bool
end

function KitCliSession(;
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=false,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    show_version::Bool=false,
    hint_surface::Symbol=:cli,
    verbosity_explicit::Bool=false,
)
    v = _resolve_kit_verbosity(; quiet=quiet, verbosity=verbosity)
    hf = hosts_file === nothing ? nothing : String(hosts_file)
    surface = _normalize_hint_surface(hint_surface)
    explicit = verbosity_explicit || quiet || verbosity !== nothing
    return KitCliSession(v === :quiet, v, yes, hf, show_version, surface, explicit)
end

function _env_flag(name::AbstractString)::Bool
    v = strip(get(ENV, String(name), ""))
    return v in ("1", "true", "yes", "on")
end

"""Default session; honors `DISTSSHKIT_QUIET`, `DISTSSHKIT_PROGRESS`, `DISTSSHKIT_VERBOSE`, `DISTSSHKIT_YES`, `DISTSSHKIT_HOSTS_FILE`."""
function default_kit_cli_session()::KitCliSession
    hosts_file = let raw = strip(get(ENV, "DISTSSHKIT_HOSTS_FILE", ""))
        isempty(raw) ? nothing : String(raw)
    end
    env_v = _env_verbosity()
    hosts_kw = (;
        yes=_env_flag("DISTSSHKIT_YES"),
        hosts_file=hosts_file,
        show_version=false,
    )
    env_v === nothing && return KitCliSession(; hosts_kw...)
    return KitCliSession(;
        quiet=env_v === :quiet,
        verbosity=env_v,
        verbosity_explicit=true,
        hosts_kw...,
    )
end

function apply_kit_cli_session!(session::KitCliSession)
    set_kit_verbosity!(session.verbosity)
    set_kit_noninteractive!(session.yes)
    return session
end

function println_kit_version(io::IO=stdout)
    println(io, "DistSSHKit $(dist_ssh_kit_version())")
    return nothing
end

const _KIT_CLI_FLAGS = (
    quiet = ("-q", "--quiet"),
    progress = ("--progress",),
    verbose = ("--verbose",),
    yes = ("-y", "--yes"),
    hosts_file = ("--hosts-file",),
    version = ("--version", "-v", "-V"),  # -V kept as deprecated alias
)

function _flag_match(arg::AbstractString, names::Tuple{Vararg{String}})::Bool
    s = String(arg)
    for n in names
        s == n && return true
    end
    return false
end

function _set_session_verbosity!(session::KitCliSession, v::Symbol)
    if session.verbosity_explicit && session.verbosity !== v
        throw(ArgumentError("cannot combine --quiet (-q), --progress, and --verbose"))
    end
    session.verbosity = v
    session.quiet = v === :quiet
    session.verbosity_explicit = true
    return session
end

"""Consume one shared CLI flag from `c`; return `true` if consumed."""
function consume_kit_cli_flag!(c::CliCursor, session::KitCliSession)::Bool
    arg = cli_current(c)
    arg === nothing && return false
    if _flag_match(arg, _KIT_CLI_FLAGS.quiet)
        _set_session_verbosity!(session, :quiet)
        cli_consume!(c)
        return true
    elseif _flag_match(arg, _KIT_CLI_FLAGS.progress)
        _set_session_verbosity!(session, :progress)
        cli_consume!(c)
        return true
    elseif _flag_match(arg, _KIT_CLI_FLAGS.verbose)
        _set_session_verbosity!(session, :verbose)
        cli_consume!(c)
        return true
    elseif _flag_match(arg, _KIT_CLI_FLAGS.yes)
        session.yes = true
        cli_consume!(c)
        return true
    elseif _flag_match(arg, _KIT_CLI_FLAGS.version)
        session.show_version = true
        cli_consume!(c)
        return true
    elseif _flag_match(arg, _KIT_CLI_FLAGS.hosts_file)
        session.hosts_file = cli_take_value!(c, arg)
        return true
    end
    return false
end

"""
Split leading shared flags from `args`.

Returns `(session, rest)` where `rest` is every non-flag token (and tokens
following flags that take values other than `--hosts-file`).
"""
function peel_kit_cli_flags(args::AbstractVector{<:AbstractString})::Tuple{KitCliSession,Vector{String}}
    session = default_kit_cli_session()
    rest = String[]
    c = CliCursor(collect(String, args))
    while !cli_at_end(c)
        if consume_kit_cli_flag!(c, session)
            continue
        end
        push!(rest, cli_current(c)::String)
        cli_consume!(c)
    end
    return session, rest
end

"""
Parse `host` or `host:N` into `(hostname, workers)`.

`N` is a worker/slot count for `drive` / `go`. `setup` / `size` keep
the hostname only (`split_host_workers_spec(…)[1]`).
"""
function split_host_workers_spec(spec::AbstractString)::Tuple{String,Union{Nothing,Int}}
    s = strip(String(spec))
    if contains(s, ':')
        parts = split(s, ':', limit=2)
        return String(parts[1]), parse(Int, parts[2])
    end
    return s, nothing
end

"""Non-comment host entries from a hosts file (may include `host:N` for drive/go)."""
function read_hosts_file_lines(
    path::AbstractString;
    surface::Symbol=:cli,
)::Vector{String}
    p = canonical_local_path(path)
    isfile(p) || throw(ArgumentError(explain_hosts_file_not_found(p; surface=surface)))
    hosts = String[]
    for line in readlines(p)
        s = strip(line)
        (isempty(s) || startswith(s, '#')) && continue
        push!(hosts, s)
    end
    isempty(hosts) && throw(ArgumentError(explain_hosts_file_empty(p; surface=surface)))
    return hosts
end

"""SSH host names from a hosts file (`host:N` → `host` only; for setup / KitSession)."""
function read_hosts_file(
    path::AbstractString;
    surface::Symbol=:cli,
)::Vector{String}
    return [split_host_workers_spec(line)[1] for line in read_hosts_file_lines(path; surface=surface)]
end

function append_hosts_file!(hosts::Vector{String}, session::KitCliSession)
    hosts_file = session.hosts_file
    hosts_file === nothing && return hosts
    append!(hosts, read_hosts_file(hosts_file; surface=session.hint_surface))
    return hosts
end

"""`println` with the same terminal gate as `writeln_both` (setup / size)."""
function kit_println(args...; io::IO=stdout)
    if kit_output_detail()
        println(io, args...)
    end
    if LOG_FILE_HANDLE[] !== nothing
        println(LOG_FILE_HANDLE[], args...)
        flush(LOG_FILE_HANDLE[])
    end
    return nothing
end

"""`print` with the same terminal gate as `writeln_both`."""
function kit_print(args...; io::IO=stdout)
    if kit_output_detail()
        print(io, args...)
    end
    if LOG_FILE_HANDLE[] !== nothing
        print(LOG_FILE_HANDLE[], args...)
        flush(LOG_FILE_HANDLE[])
    end
    return nothing
end

"""
Prompt on stdin; return `true` if confirmed.

With `--yes` / `DISTSSHKIT_YES`, always returns `true`.
`keyword=nothing` → accept `y` / `yes` (case-insensitive).
Otherwise the answer must match `keyword` exactly.
"""
function kit_confirm(prompt::AbstractString; keyword::Union{Nothing,String}=nothing)::Bool
    kit_noninteractive() && return true
    kit_print(prompt)
    flush(stdout)
    answer = strip(readline())
    if keyword === nothing
        return lowercase(answer) in ("y", "yes")
    end
    return answer == keyword
end

function kit_confirm!(prompt::AbstractString; keyword::Union{Nothing,String}=nothing)::Bool
    kit_confirm(prompt; keyword=keyword) || return false
    return true
end
