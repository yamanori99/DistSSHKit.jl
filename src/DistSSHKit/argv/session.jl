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
const KIT_TIME_HELP =
    "Time table after the run (-q hides it); replay: progress DIR"
const KIT_HOSTS_FLAG_HELP =
    "--hosts CSV         parent[:N] / child:NAME[:N]"
const KIT_QUIET_ENV_HELP =
    "DISTSSHKIT_QUIET                  Same as --quiet"
const KIT_PROGRESS_ENV_HELP =
    "DISTSSHKIT_PROGRESS               Same as --progress"
const KIT_VERBOSE_ENV_HELP =
    "DISTSSHKIT_VERBOSE                Same as --verbose"
const KIT_HOSTS_ENV_HELP =
    "DISTSSHKIT_HOSTS                  Same as --hosts"
const KIT_SKIP_PKILL_ENV_HELP =
    "DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL  skip leftover-worker pkill"
const KIT_JOBS_ENV_HELP =
    "DISTSSHKIT_JOBS                   max concurrent host jobs (default 1)"
const KIT_REQUIRE_ALL_HOSTS_ENV_HELP =
    "DISTSSHKIT_REQUIRE_ALL_HOSTS      Same as --require-all-hosts"

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
    hosts_flag::Vector{String}
end

function KitCliSession(;
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=false,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    show_version::Bool=false,
    hint_surface::Symbol=:cli,
    verbosity_explicit::Bool=false,
    hosts_flag::AbstractVector{<:AbstractString}=String[],
)
    v = _resolve_kit_verbosity(; quiet=quiet, verbosity=verbosity)
    hf = hosts_file === nothing ? nothing : String(hosts_file)
    surface = _normalize_hint_surface(hint_surface)
    explicit = verbosity_explicit || quiet || verbosity !== nothing
    return KitCliSession(
        v === :quiet,
        v,
        yes,
        hf,
        show_version,
        surface,
        explicit,
        String[String(h) for h in hosts_flag],
    )
end

function _env_flag(name::AbstractString)::Bool
    v = strip(get(ENV, String(name), ""))
    return v in ("1", "true", "yes", "on")
end

"""Max concurrent SSH host jobs (`DISTSSHKIT_JOBS`, default 1)."""
function kit_host_jobs()::Int
    raw = strip(get(ENV, "DISTSSHKIT_JOBS", "1"))
    n = tryparse(Int, raw)
    (n === nothing || n < 1) && return 1
    return n
end

"""Call `f(i, host)` for each host, at most `kit_host_jobs()` at once (1 → sequential)."""
function map_host_jobs(f, hosts::Vector{String})
    n = length(hosts)
    n == 0 && return nothing
    jobs = min(kit_host_jobs(), n)
    if jobs == 1
        for i in 1:n
            f(i, hosts[i])
        end
        return nothing
    end
    sem = Base.Semaphore(jobs)
    @sync for i in 1:n
        @async begin
            Base.acquire(sem)
            try
                f(i, hosts[i])
            finally
                Base.release(sem)
            end
        end
    end
    return nothing
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

"""Print `DistSSHKit <version>` (same as `julia -m DistSSHKit --version`)."""
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
    hosts = ("--hosts",),
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
    elseif _flag_match(arg, _KIT_CLI_FLAGS.hosts)
        append!(session.hosts_flag, split_hosts_csv(cli_take_value!(c, arg)))
        return true
    end
    return false
end

"""
Split leading shared flags from `args`.

Returns `(session, rest)` where `rest` is every non-flag token (and tokens
following flags that take values other than `--hosts-file` / `--hosts`).
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

"""Split a `--hosts` / `DISTSSHKIT_HOSTS` CSV into tokens (empty pieces dropped)."""
function split_hosts_csv(raw::AbstractString)::Vector{String}
    out = String[]
    for h in split(String(raw), ',')
        s = strip(h)
        !isempty(s) && push!(out, s)
    end
    return out
end

"""
Parse `host` or `host:N` into `(hostname, workers)`.

`N` is a worker/slot count for `drive` / `go`. `setup` / `size` keep
the hostname only (`split_worker_token(…)[1]`).
"""
function split_worker_token(spec::AbstractString)::Tuple{String,Union{Nothing,Int}}
    s = strip(String(spec))
    if contains(s, ':')
        parts = split(s, ':', limit=2)
        return String(parts[1]), parse(Int, parts[2])
    end
    return s, nothing
end

"""
    host_tokens(hosts::AbstractVector{<:AbstractString}) -> Vector{String}
    host_tokens(hosts::AbstractVector{Tuple{String,Union{Int,Nothing}}}; parent_workers=0)
    host_tokens(parsed; kind::Symbol) -> Vector{String}

Rebuild CLI host tokens for [`execute!`](@ref).

Go tokens are the parser strings. Drive tuples plus `parent_workers` emit
`parent:N` then `child:NAME[:N]`; omitted counts stay omitted (no invented `:1`).
`kind` must be `:go` or `:drive`.
"""
function host_tokens(hosts::AbstractVector{<:AbstractString})::Vector{String}
    return String[String(h) for h in hosts]
end

function host_tokens(
    hosts::AbstractVector{Tuple{String,Union{Int,Nothing}}};
    parent_workers::Integer=0,
)::Vector{String}
    specs = String[]
    lw = Int(parent_workers)
    lw > 0 && push!(specs, format_placement_token(:parent, PARENT_HOST_NAME, lw))
    for pair in hosts
        host = pair[1]
        n = pair[2]
        push!(specs, format_placement_token(:child, host, n))
    end
    return specs
end

function host_tokens(parsed; kind::Symbol)::Vector{String}
    if kind === :go
        return host_tokens(parsed.hosts::AbstractVector{<:AbstractString})
    elseif kind === :drive
        return host_tokens(
            parsed.hosts::AbstractVector{Tuple{String,Union{Int,Nothing}}};
            parent_workers=parsed.parent_workers,
        )
    end
    throw(ArgumentError("host_tokens: kind must be :go or :drive, got $(repr(kind))"))
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
    return [split_worker_token(line)[1] for line in read_hosts_file_lines(path; surface=surface)]
end

function _kit_host_token(
    tok::AbstractString,
    keep_counts::Bool;
    roles::Bool=false,
)::String
    keep_counts && return String(tok)
    if roles
        p = parse_placement_token(tok)
        return p.role === :parent ? PARENT_HOST_NAME : p.name
    end
    return split_worker_token(tok)[1]
end

"""`--hosts`, `DISTSSHKIT_HOSTS`, then `--hosts-file` / `DISTSSHKIT_HOSTS_FILE`.

`keep_counts=true` (go / drive) keeps tokens as written. `false` (setup / size)
strips `:N`. Size passes `roles=true` so `child:NAME[:N]` becomes `NAME` and
`parent` stays `parent`. Setup keeps bare SSH names (`roles=false`).
"""
function kit_host_source_tokens(
    session::KitCliSession;
    keep_counts::Bool=true,
    roles::Bool=false,
)::Vector{String}
    out = String[_kit_host_token(t, keep_counts; roles=roles) for t in session.hosts_flag]
    for t in split_hosts_csv(get(ENV, "DISTSSHKIT_HOSTS", ""))
        push!(out, _kit_host_token(t, keep_counts; roles=roles))
    end
    hosts_file = session.hosts_file
    if hosts_file !== nothing
        if keep_counts
            append!(out, read_hosts_file_lines(hosts_file; surface=session.hint_surface))
        elseif roles
            for line in read_hosts_file_lines(hosts_file; surface=session.hint_surface)
                push!(out, _kit_host_token(line, false; roles=true))
            end
        else
            append!(out, read_hosts_file(hosts_file; surface=session.hint_surface))
        end
    end
    return out
end

function append_kit_host_sources!(
    hosts::Vector{String},
    session::KitCliSession;
    keep_counts::Bool=true,
    roles::Bool=false,
)
    append!(hosts, kit_host_source_tokens(session; keep_counts=keep_counts, roles=roles))
    return hosts
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

The prompt is always written to the terminal (quiet / progress / verbose).
Do not route it through [`kit_print`](@ref) (`:verbose` only).

With `--yes` / `DISTSSHKIT_YES`, always returns `true` without prompting.
`keyword=nothing` → accept `y` / `yes` (case-insensitive).
Otherwise the answer must match `keyword` exactly.
"""
function kit_confirm(prompt::AbstractString; keyword::Union{Nothing,String}=nothing)::Bool
    kit_noninteractive() && return true
    print(stdout, prompt)
    flush(stdout)
    if LOG_FILE_HANDLE[] !== nothing
        print(LOG_FILE_HANDLE[], prompt)
        flush(LOG_FILE_HANDLE[])
    end
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
