# SSH configuration

"""Build SSH options. `request_tty=false` (default) adds `RequestTTY=no`."""
function build_ssh_opts(; request_tty::Bool=false)
    custom = strip(get(ENV, "DISTRIBUTED_SSH_OPTS", ""))
    if isempty(custom)
        opts = String["-o", "BatchMode=yes"]
        if !request_tty
            push!(opts, "-o", "RequestTTY=no")
        end
        append!(opts, (
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=60",
            "-o", "ServerAliveCountMax=10",
            "-o", "TCPKeepAlive=yes",
        ))
        return opts
    end
    return split(custom)
end

"""
    ssh_opts(; request_tty=false) -> Vector{String}

SSH argv flags for `ssh` / `scp` / rsync `-e`.

Reads `DISTRIBUTED_SSH_OPTS` **live** (not frozen at package precompile). Prefer
this over a `const` so E2E / ProxyJump overrides apply in the same process.

A non-empty `DISTRIBUTED_SSH_OPTS` **replaces** the default vector (it is not
merged). `request_tty` only changes the default vector: `false` includes
`-o RequestTTY=no`; `true` omits it so a caller may put `ssh -t` before or
after these flags. The ENV replacement is unchanged (if it contains
`RequestTTY=no`, put `-t` **after** the vector). Use `-o RequestTTY=no`,
not `ssh -T`: these flags are also passed to `scp` (`scp -T` is unrelated).
Does not insert `-t` (that flag is `ssh`-only).
"""
function ssh_opts(; request_tty::Bool=false)::Vector{String}
    return String[String(x) for x in build_ssh_opts(; request_tty=request_tty)]
end

"""`ssh` / `rsync` / `git` on `PATH`, or throw `ArgumentError`."""
function _host_tool_exe(name::AbstractString)::String
    n = _normalize_host_tool(name)
    exe = Sys.which(n)
    exe === nothing && throw(ArgumentError(explain_host_tool_missing(n)))
    return exe
end

_host_tool_present(name::AbstractString)::Bool = Sys.which(_normalize_host_tool(name)) !== nothing

_rethrow_missing_host_tool(e) = e isa ArgumentError && rethrow(e)

"""`ssh` on `PATH`, or throw `ArgumentError`."""
_ssh_exe()::String = _host_tool_exe("ssh")

function _host_tool_cmd(name::AbstractString, args::AbstractVector)::Cmd
    return Cmd(append!([_host_tool_exe(name)], String[String(a) for a in args]))
end

_git_cmd(args::AbstractVector)::Cmd = _host_tool_cmd("git", args)
_ssh_cmd(args::AbstractVector)::Cmd = _host_tool_cmd("ssh", args)
_scp_cmd(args::AbstractVector)::Cmd = _host_tool_cmd("scp", args)

"""
Effective SSH `User` for `host` from `ssh -G` (config / defaults).

Returns `nothing` when the query fails. Used so [`ssh_addprocs_machine`](@ref)
can pass `user@host` into `Distributed.addprocs` (which otherwise prefixes the
local `\$USER` and overrides SSH config `User`).
"""
function ssh_config_user(host::AbstractString)::Union{Nothing,String}
    h = String(strip(host))
    isempty(h) && return nothing
    try
        # -n: no stdin; -G dumps effective config (User, HostName, …).
        out = read(_ssh_cmd(["-n", ssh_opts()..., "-G", h]), String)
        for line in eachsplit(out, '\n'; keepempty=false)
            if startswith(line, "user ")
                u = strip(SubString(line, 6))
                return isempty(u) ? nothing : String(u)
            end
        end
    catch
    end
    return nothing
end

"""
Machine string for `Distributed.addprocs` over SSH.

If `host` already contains `@`, it is returned unchanged. Otherwise the effective
SSH config user (via [`ssh_config_user`](@ref)) is prefixed so tunneling does not
authenticate as the local login name.

# Examples
```jldoctest
julia> using DistSSHKit

julia> DistSSHKit.ssh_addprocs_machine("dev@host1")
"dev@host1"
```
"""
function ssh_addprocs_machine(host::AbstractString)::String
    h = String(strip(host))
    isempty(h) && return h
    occursin('@', h) && return h
    u = ssh_config_user(h)
    return u === nothing ? h : string(u, '@', h)
end

# Stale Distributed.jl worker cleanup (local + SSH)

"""Regex patterns for Julia `Distributed.addprocs` worker command lines."""
const JULIA_WORKER_PKILL_PATTERNS = ("julia.*--worker", "julia.*--bind-to")

"""
Kill local Julia worker processes matching [`JULIA_WORKER_PKILL_PATTERNS`](@ref).

Used by `setup --cleanup` (explicit machine-wide sweep). `drive` does not call
this: local workers are torn down with `rmprocs`. `pkill -f` may match its own
argv (patterns contain `--worker` / `--bind-to`); exit status is ignored.
"""
function _pkill_local_julia_workers!()
    for pattern in JULIA_WORKER_PKILL_PATTERNS
        try
            run(pipeline(Cmd(["pkill", "-9", "-f", pattern]); stdout=devnull, stderr=devnull))
        catch
        end
    end
    return nothing
end

"""Return whether a trivial `ssh YourHost true` succeeds."""
function _remote_ssh_ok(host::String)::Bool
    try
        run(pipeline(_host_sync_remote_shell_cmd(host, "true"); stdout=devnull, stderr=devnull))
        return true
    catch e
        _rethrow_missing_host_tool(e)
        return false
    end
end

"""
Kill stale Julia workers on `host` via SSH.

Runs one `pkill` per pattern in separate SSH sessions. A single remote shell line
`pkill -f 'julia.*--worker'; pkill …; true` is unsafe: `pkill -f` regex matches its
own argv and SIGKILLs the session before `true` (ssh exit 255, drive shows
`(unavailable)` even though the host is reachable).

Returns `false` only when SSH itself fails; `true` when the host was reached and
cleanup was attempted (including no matching processes).
"""
function _pkill_remote_julia_workers!(host::String)::Bool
    if !_remote_ssh_ok(host)
        return false
    end
    for pattern in JULIA_WORKER_PKILL_PATTERNS
        inner = "pkill -9 -f $(Base.shell_escape(pattern))"
        try
            run(pipeline(_host_sync_remote_shell_cmd(host, inner); stdout=devnull, stderr=devnull))
        catch e
            _rethrow_missing_host_tool(e)
        end
    end
    return true
end

# Visible on worker / go-slot argv so `pkill -f` can be run-scoped (see `terminate!`).
const KIT_JOB_CMDLINE_MARK::String = "distsshkit-job:"

"""`DISTSSHKIT_JOB_ID` if set and non-empty. Restricted charset for `pkill -f`."""
function _parse_kit_job_id(raw::AbstractString)::String
    s = strip(String(raw))
    isempty(s) && throw(ArgumentError("job_id must be non-empty"))
    occursin(r"^[A-Za-z0-9._:@+-]+$", s) || throw(ArgumentError(
        "job_id / DISTSSHKIT_JOB_ID must match [A-Za-z0-9._:@+-]+, got $(repr(raw))",
    ))
    return s
end

function resolved_kit_job_id()::Union{Nothing,String}
    raw = strip(get(ENV, "DISTSSHKIT_JOB_ID", ""))
    isempty(raw) && return nothing
    return _parse_kit_job_id(raw)
end

"""Julia comment whose text is [`kit_job_pkill_pattern`](@ref). Eval is a no-op."""
function kit_job_mark_comment(job_id::AbstractString)::String
    return "#" * kit_job_pkill_pattern(job_id)
end

"""Drive-worker `exeflags` word: `--eval` of [`kit_job_mark_comment`](@ref).

A comment-only `--eval` does not replace Distributed's worker bootstrap.
Do not put real code here, and do not pass this flag to a go slot — any
`--eval` makes Julia skip `programfile`. Go uses [`kit_write_job_mark_file`](@ref)
plus `-L` instead, so the user script stays the program file.
`DISTSSHKIT_JOB_ID` is process env (`addenv` / `addprocs` `env`), not `--eval`.
"""
function kit_job_eval_arg(job_id::AbstractString)::String
    return "--eval=$(kit_job_mark_comment(job_id))"
end

"""Write a no-op Julia file named [`kit_job_pkill_pattern`](@ref) under `dir`.

Go passes `-L` this path so `pkill -f` sees the tag without `--eval`.
"""
function kit_write_job_mark_file(dir::AbstractString, job_id::AbstractString)::String
    path = joinpath(dir, kit_job_pkill_pattern(job_id))
    mkpath(dir)
    write(path, kit_job_mark_comment(job_id) * "\n")
    return path
end

function kit_job_pkill_pattern(job_id::AbstractString)::String
    return string(KIT_JOB_CMDLINE_MARK, String(job_id))
end

function _drive_worker_env()
    id = resolved_kit_job_id()
    id === nothing && return Pair{String,String}[]
    return ["DISTSSHKIT_JOB_ID" => id]
end

function _drive_worker_exeflags(project::AbstractString)
    id = resolved_kit_job_id()
    id === nothing && return `--project=$project`
    return `--project=$project $(kit_job_eval_arg(id))`
end

function _pkill_pattern!(pattern::AbstractString)
    Sys.isunix() || return nothing
    try
        run(pipeline(Cmd(["pkill", "-9", "-f", String(pattern)]); stdout=devnull, stderr=devnull))
    catch
    end
    return nothing
end

"""Kill local processes whose argv contains this run's job mark. No-op if `job_id` is unset."""
function _pkill_local_tagged_workers!(job_id::AbstractString)
    _pkill_pattern!(kit_job_pkill_pattern(job_id))
    return nothing
end

"""SSH `pkill -f` for this run's job mark only (never `julia.*--worker`)."""
function _pkill_remote_tagged_workers!(host::String, job_id::AbstractString)::Bool
    if !_remote_ssh_ok(host)
        return false
    end
    inner = "pkill -9 -f $(Base.shell_escape(kit_job_pkill_pattern(job_id)))"
    try
        run(pipeline(_host_sync_remote_shell_cmd(host, inner); stdout=devnull, stderr=devnull))
    catch e
        _rethrow_missing_host_tool(e)
    end
    return true
end

"""Parse `julia --version` output (e.g. `"julia version 1.12.6"`) into a `VersionNumber`.
Returns `nothing` if the text doesn't match the expected pattern.

# Examples
```jldoctest
julia> using DistSSHKit

julia> DistSSHKit.parse_julia_version("julia version 1.12.6")
v"1.12.6"

julia> DistSSHKit.parse_julia_version("not julia") === nothing
true
```
"""
function parse_julia_version(version_output::AbstractString)::Union{Nothing,VersionNumber}
    m = match(r"julia version (\d+\.\d+\.\d+)", String(version_output))
    m === nothing && return nothing
    cap = m.captures[1]
    cap isa AbstractString || return nothing
    try
        return VersionNumber(String(cap))
    catch
        return nothing
    end
end

"""Get the Julia version on a remote host by running `julia_path --version` over SSH.
Returns `nothing` on any failure (SSH, missing binary, unparseable output)."""
function get_remote_julia_version(host::String, julia_path::AbstractString)::Union{Nothing,VersionNumber}
    try
        result = read(pipeline(_ssh_cmd([ssh_opts()..., host, String(julia_path), "--version"]); stderr=devnull), String)
        return parse_julia_version(result)
    catch
        return nothing
    end
end

"""
Ordered remote Julia path candidates for `uname -s` output (Darwin vs Linux).

Prefers juliaup (`\$HOME/.juliaup/bin/julia`), then platform paths. Homebrew
only on Darwin. Callers still verify with `test -x` and `--version` before
accepting a hit.
"""
function remote_julia_candidates(uname_s::AbstractString)::Vector{String}
    os = lowercase(strip(String(uname_s)))
    juliaup = raw"$HOME/.juliaup/bin/julia"
    if startswith(os, "darwin")
        return String[juliaup, "/opt/homebrew/bin/julia", "/usr/local/bin/julia", "/usr/bin/julia"]
    end
    return String[juliaup, "/usr/bin/julia", "/usr/local/bin/julia"]
end

"""Whether `path` looks like an auto-detect request (`nothing` / empty / `auto`)."""
_julia_spec_is_auto(::Nothing)::Bool = true
function _julia_spec_is_auto(spec::AbstractString)::Bool
    s = strip(String(spec))
    return isempty(s) || lowercase(s) == "auto"
end

"""
Resolve the Julia binary on this controller (`nothing` / `"auto"` / empty →
the running process). Explicit paths are kept as given after usability check.

Throws `ArgumentError` when the binary is missing or `--version` does not parse.
"""
function resolve_controller_julia(spec::Union{Nothing,AbstractString}=nothing)::String
    path = if _julia_spec_is_auto(spec)
        String(something(Base.julia_cmd().exec[1], ""))
    else
        String(strip(String(spec::AbstractString)))
    end
    isempty(path) && throw(ArgumentError("Julia binary not resolved on controller"))
    abs = isabspath(path) ? path : abspath(path)
    try
        out = read(pipeline(Cmd([abs, "--version"]); stderr=devnull), String)
        parse_julia_version(out) === nothing && throw(ArgumentError(
            "controller Julia at $(abs) did not report a parseable --version",
        ))
    catch e
        e isa ArgumentError && rethrow()
        throw(ArgumentError("controller Julia not usable at $(abs): $(sprint(showerror, e))"))
    end
    return abs
end

"""
Resolve Julia on SSH `host`.

`nothing` / `"auto"` / empty → `detect_julia_path`. Explicit path must
pass remote `--version`. Returns `nothing` when auto-detect fails (no bare
`"julia"` fallback).
"""
function resolve_remote_julia(
    host::AbstractString,
    spec::Union{Nothing,AbstractString}=nothing,
)::Union{Nothing,String}
    h = String(host)
    if _julia_spec_is_auto(spec)
        return detect_julia_path(h)
    end
    path = String(strip(String(spec::AbstractString)))
    isempty(path) && return nothing
    get_remote_julia_version(h, path) === nothing && return nothing
    return path
end

function _remote_julia_path_sh(path::AbstractString)::String
    s = String(path)
    if startswith(s, raw"$HOME") || startswith(s, "\$HOME")
        return string("\"", s, "\"")
    end
    return Base.shell_escape(s)
end

function _remote_julia_candidates_sh(uname_s::AbstractString)::String
    return sprint() do io
        first = true
        for p in remote_julia_candidates(uname_s)
            first || print(io, ' ')
            first = false
            print(io, _remote_julia_path_sh(p))
        end
    end
end

"""POSIX single-quote a word so remote `sh` does not parse metacharacters."""
function _remote_sh_quote(word::AbstractString)::String
    return sprint() do io
        print(io, '\'')
        for c in String(word)
            if c == '\''
                print(io, "'\\''")
            else
                print(io, c)
            end
        end
        print(io, '\'')
    end
end

function _remote_argv_sh(argv::AbstractVector{<:AbstractString})::String
    return sprint() do io
        first = true
        for a in argv
            first || print(io, ' ')
            first = false
            print(io, _remote_sh_quote(a))
        end
    end
end

"""Remote `sh -c` body: find Julia (same candidates as detect) then `exec` it with `argv`."""
function _run_on_host_remote_sh(
    argv::AbstractVector{<:AbstractString};
    julia::Union{Nothing,AbstractString}=nothing,
    detect::Bool=true,
)::String
    extra = _remote_argv_sh(argv)
    spec = julia
    use_detect = detect && _julia_spec_is_auto(spec)
    if use_detect
        darwin_set = sprint() do io
            print(io, "set -- ")
            print(io, _remote_julia_candidates_sh("Darwin"))
        end
        linux_set = sprint() do io
            print(io, "set -- ")
            print(io, _remote_julia_candidates_sh("Linux"))
        end
        return sprint() do io
            print(io, "u=\$(uname -s); case \"\$u\" in Darwin*) ")
            print(io, darwin_set)
            print(io, " ;; *) ")
            print(io, linux_set)
            print(io, " ;; esac; JULIA=; for p in \"\$@\"; do if [ -x \"\$p\" ] && \"\$p\" --version 2>/dev/null | grep -q 'julia version'; then JULIA=\$p; break; fi; done; ")
            print(io, "if [ -z \"\$JULIA\" ]; then JULIA=\$(command -v julia 2>/dev/null || true); fi; ")
            print(io, "[ -n \"\$JULIA\" ] && [ -x \"\$JULIA\" ] && \"\$JULIA\" --version 2>/dev/null | grep -q 'julia version' || exit 127; exec \"\$JULIA\"")
            isempty(extra) || (print(io, ' '); print(io, extra))
        end
    end
    path = spec === nothing ? "" : String(strip(String(spec)))
    isempty(path) && throw(ArgumentError(
        "run_on_host: detect=false requires julia= to a remote path (not auto)",
    ))
    q = Base.shell_escape(path)
    return sprint() do io
        print(io, "JULIA="); print(io, q)
        print(io, "; [ -x \"\$JULIA\" ] && \"\$JULIA\" --version 2>/dev/null | grep -q 'julia version' || exit 127; exec \"\$JULIA\"")
        isempty(extra) || (print(io, ' '); print(io, extra))
    end
end

"""
    run_on_host(host, argv; julia=nothing, detect=true, tty=false, wait=true) -> Base.Process

One SSH connection: resolve remote Julia the same way as
[`resolve_remote_julia`](@ref) / `detect_julia_path`, then `exec` it
with `argv` (Julia flags / script / args). Does not replace
`resolve_remote_julia` when the caller only needs the path.

`julia=nothing` / `"auto"` with `detect=true` probes candidates on the remote.
`detect=false` requires an explicit path. `tty=true` adds `ssh -t`.
Process-local detect cache is not used (a new CLI process never hits it).

SSH is `ignorestatus`: a non-zero remote or ssh exit returns the `Process`
(`.exitcode`) instead of throwing `ProcessFailedException`. Missing `ssh` on
`PATH` throws `ArgumentError`.
"""
function run_on_host(
    host::AbstractString,
    argv::AbstractVector{<:AbstractString}=String[];
    julia::Union{Nothing,AbstractString}=nothing,
    detect::Bool=true,
    tty::Bool=false,
    wait::Bool=true,
)::Base.Process
    h = String(strip(host))
    isempty(h) && throw(ArgumentError("run_on_host: host must be non-empty"))
    inner = _run_on_host_remote_sh(argv; julia=julia, detect=detect)
    args = String[ssh_opts(; request_tty=tty)...]
    tty && push!(args, "-t")
    push!(args, h, inner)
    return run(ignorestatus(_ssh_cmd(args)); wait=wait)
end

# Process-local auto-detect results (`nothing` included). Same host in
# `size!` then `drive!` / `--check` then `--instantiate` skips repeat SSH.
const _DETECT_JULIA_PATH_CACHE = Dict{String,Union{Nothing,String}}()

"""Drop cached `detect_julia_path` results (`host=nothing` → all hosts)."""
function clear_detect_julia_path_cache!(host::Union{Nothing,AbstractString}=nothing)
    if host === nothing
        empty!(_DETECT_JULIA_PATH_CACHE)
    else
        delete!(_DETECT_JULIA_PATH_CACHE, String(strip(host)))
    end
    return nothing
end

"""Detect Julia path on remote host via SSH (executable + parseable `--version`)."""
function detect_julia_path(host::String)::Union{Nothing,String}
    h = String(strip(host))
    isempty(h) && return nothing
    if haskey(_DETECT_JULIA_PATH_CACHE, h)
        return _DETECT_JULIA_PATH_CACHE[h]
    end
    found = _detect_julia_path_uncached(h)
    _DETECT_JULIA_PATH_CACHE[h] = found
    return found
end

"""`--version` over the setup SSH transport (honors `DISTSSHKIT_TEST_SSH`)."""
function _remote_julia_reports_version(host::String, path::AbstractString)::Bool
    pq = _remote_shell_path_word(String(path))
    try
        out = read(
            pipeline(_host_sync_remote_shell_cmd(host, "$pq --version"); stderr=devnull),
            String,
        )
        return parse_julia_version(out) !== nothing
    catch
        return false
    end
end

function _detect_julia_path_uncached(host::String)::Union{Nothing,String}
    uname_s = try
        strip(read(
            pipeline(_host_sync_remote_shell_cmd(host, "uname -s"); stderr=devnull),
            String,
        ))
    catch
        ""
    end

    if !isempty(uname_s)
        for path in remote_julia_candidates(uname_s)
            try
                result = read(pipeline(
                    _host_sync_remote_shell_cmd(host, "test -x $path && echo $path");
                    stderr=devnull,
                ), String)
                found = strip(result)
                isempty(found) && continue
                _remote_julia_reports_version(host, found) || continue
                return String(found)
            catch
                continue
            end
        end
    end
    try
        result = read(pipeline(
            _host_sync_remote_shell_cmd(host, "command -v julia || which julia");
            stderr=devnull,
        ), String)
        p = strip(result)
        isempty(p) && return nothing
        _remote_julia_reports_version(host, p) || return nothing
        return String(p)
    catch
        return nothing
    end
end

# Git utilities

"""Get local git commit hash (`short=nothing` → full hash, else `git rev-parse --short`)."""
function get_local_git_hash(proj_dir::AbstractString; short::Union{Nothing,Int}=nothing)::Union{Nothing,String}
    _host_tool_present("git") || return nothing
    resolved = canonical_local_path(proj_dir)
    try
        cmd = if short === nothing
            _git_cmd(["-C", resolved, "rev-parse", "HEAD"])
        else
            _git_cmd(["-C", resolved, "rev-parse", "--short=$(short)", "HEAD"])
        end
        s = strip(read(pipeline(cmd; stderr=devnull), String))
        return isempty(s) ? nothing : s
    catch
        return nothing
    end
end

"""Whether the local git working tree at `proj_dir` is clean (no uncommitted changes).

Returns `true` if clean, if `git` is missing, or if `proj_dir` is not a git work tree.
If this is a work tree but `git status` fails, returns `false` so `--require-git` /
`setup --check` still warn. This check does not block a run."""
function local_git_clean(proj_dir::AbstractString)::Bool
    _host_tool_present("git") || return true
    resolved = canonical_local_path(proj_dir)
    inside = try
        strip(read(pipeline(
            _git_cmd(["-C", resolved, "rev-parse", "--is-inside-work-tree"]);
            stderr=devnull,
        ), String))
    catch
        return true
    end
    inside == "true" || return true
    try
        result = read(pipeline(_git_cmd(["-C", resolved, "status", "--porcelain"]); stderr=devnull), String)
        return isempty(strip(result))
    catch
        return false
    end
end

"""
Shell word for `path` on the remote login shell.

A `~` / `~user` prefix stays unquoted so the remote shell expands it. The rest
of a `~/…` path is `Base.shell_escape`d (`~/'Repo With Spaces'`). Other paths
are escaped in full.
"""
function _remote_shell_path_word(path::AbstractString)::String
    p = strip(String(path))
    startswith(p, "~") || return Base.shell_escape(p)
    slash = findfirst('/', p)
    if slash === nothing
        occursin(r"[\s'\"\\]", p) && return Base.shell_escape(p)
        return p
    end
    prefix = p[1:slash-1]
    rest = p[slash+1:end]
    occursin(r"[\s'\"\\]", prefix) && return Base.shell_escape(p)
    isempty(rest) && return prefix * "/"
    return prefix * "/" * Base.shell_escape(rest)
end

"""
Build a remote shell snippet that resolves `remote_path` to an absolute path.

Works for directories and regular files (`cd` alone fails on file paths).
A `~/…` layout that does not exist yet still expands `~` (`printf`); collect
then `mkdir -p`. Other missing paths still fail.
"""
function _remote_abs_path_resolve_shell(remote_path::AbstractString)::String
    path = strip(String(remote_path))
    pq = _remote_shell_path_word(path)
    exist = "if test -d $pq; then cd $pq && pwd; elif test -e $pq; then d=\$(dirname $pq) && b=\$(basename $pq) && cd \"\$d\" && echo \"\$(pwd)/\$b\"; else exit 1; fi"
    startswith(path, "~") || return exist
    return "if test -d $pq; then cd $pq && pwd; elif test -e $pq; then d=\$(dirname $pq) && b=\$(basename $pq) && cd \"\$d\" && echo \"\$(pwd)/\$b\"; else printf '%s\\n' $pq; fi"
end

"""
Map `local_abs` under `local_repo_root` to an absolute path on `host`.

For `parent`, returns the canonical local path. For SSH hosts, uses
[`remote_path_for_ssh_collect`](@ref) then [`resolve_remote_abs_path_on_host`](@ref).
Returns `nothing` when the remote path cannot be resolved.
"""
function resolve_host_path_abs(
    host::AbstractString,
    local_abs::AbstractString,
    local_repo_root::AbstractString,
)::Union{Nothing,String}
    path_local = canonical_local_path(local_abs)
    h = String(strip(host))
    is_parent_host_name(h) && return path_local
    mapped = remote_path_for_ssh_collect(path_local, local_repo_root)
    return resolve_remote_abs_path_on_host(h, mapped)
end

"""
Absolute project root for `addprocs` / size probe on `host`.

Equivalent to [`resolve_host_path_abs`](@ref)`(host, local_project, local_project)`.
"""
function resolve_host_project_abs(
    host::AbstractString,
    local_project::AbstractString,
)::Union{Nothing,String}
    return resolve_host_path_abs(host, local_project, local_project)
end

"""
Resolve `remote_path` to an absolute path on `host` via SSH (`cd … && pwd`).

Returns `remote_path` unchanged when it is already absolute (`/` prefix).
A `~/…` layout is expanded on the host even if the tree is not created yet.
Returns `nothing` when SSH fails, or when a non-tilde path does not exist.
"""
function resolve_remote_abs_path_on_host(host::String, remote_path::AbstractString)::Union{Nothing,String}
    path = strip(String(remote_path))
    isempty(path) && return nothing
    startswith(path, "/") && return path
    try
        inner = _remote_abs_path_resolve_shell(path)
        s = strip(read(pipeline(_ssh_cmd([ssh_opts()..., host, inner]); stderr=devnull), String))
        isempty(s) && return nothing
        return String(s)
    catch
        return nothing
    end
end

"""Remote login-shell snippet for [`get_remote_git_hash`](@ref)."""
function _remote_git_hash_inner(
    remote_repo_dir::AbstractString;
    short::Union{Nothing,Int}=nothing,
)::String
    dir = strip(String(remote_repo_dir))
    pq = _remote_shell_path_word(dir)
    rev = short === nothing ? "HEAD" : "--short=$(short) HEAD"
    return if startswith(dir, "~")
        "cd $pq && git rev-parse $rev"
    else
        "git -C $pq rev-parse $rev"
    end
end

"""
Get remote git commit hash via SSH.

`remote_repo_dir` starting with `~` uses `cd DIR && git rev-parse …` (shell expands `~`);
otherwise uses `git -C DIR rev-parse …` (absolute path on the remote, same layout as local).
"""
function get_remote_git_hash(host::String, remote_repo_dir::AbstractString; short::Union{Nothing,Int}=nothing)::Union{Nothing,String}
    try
        inner = _remote_git_hash_inner(remote_repo_dir; short=short)
        s = strip(read(pipeline(_ssh_cmd([ssh_opts()..., host, inner]); stderr=devnull), String))
        return isempty(s) ? nothing : s
    catch
        return nothing
    end
end

# Remote resource detection

"""Get total memory (GB) for a remote host via SSH."""
function get_remote_total_gb(host::String)
    try
        s = strip(read(pipeline(_ssh_cmd([ssh_opts()..., host,
            "sysctl -n hw.memsize 2>/dev/null || awk '/MemTotal/{print \$2*1024}' /proc/meminfo 2>/dev/null"]);
            stderr=devnull), String))
        isempty(s) && return nothing
        return parse(Float64, s) / 1024^3
    catch end
    return nothing
end

"""Get CPU core count for a remote host via SSH."""
function get_remote_nproc(host::String)
    try
        s = strip(read(pipeline(_ssh_cmd([ssh_opts()..., host,
            "sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null"]); stderr=devnull), String))
        isempty(s) && return nothing
        return parse(Int, s)
    catch end
    return nothing
end

"""Get total memory (GB) and CPU cores for localhost."""
function get_local_resources()
    total_gb = Sys.total_memory() / 1024^3
    nproc = try
        s = strip(read(pipeline(`sysctl -n hw.ncpu`, stderr=devnull), String))
        isempty(s) ? Sys.CPU_THREADS : parse(Int, s)
    catch
        Sys.CPU_THREADS
    end
    return (total_gb=total_gb, nproc=nproc)
end

# Remote path resolution & result collection

"""
List all files under `remote_root` on `host` recursively via SSH `find`, returning
`(remote_abs_path, relative_path)` pairs (relative to `remote_root`).

Tilde roots (`~/…`) are expanded **on the remote** before `find`. Matching must
not use local `relpath`/`abspath` against a tilde base (that expands `~` to the
controller home and yields bogus `../…` relatives).
"""
function collect_tree_remote_files_ssh(host::AbstractString, remote_root::AbstractString)::Vector{Tuple{String,String}}
    hp = String(host)
    rr = ensure_remote_abs_path(hp, remote_root)
    rr === nothing && return Tuple{String,String}[]
    rr = rr::String
    pq = _remote_shell_path_word(rr)
    out = read(
        pipeline(
            _host_sync_remote_shell_cmd(hp, "find $pq -type f -print");
            stderr=devnull,
        ),
        String,
    )
    sep = endswith(rr, "/") ? rr : (rr * "/")
    pairs = Tuple{String,String}[]
    for line in split(out, '\n')
        p = String(strip(line))
        isempty(p) && continue
        rel = startswith(p, sep) ? p[length(sep)+1:end] : String(relpath(p, rr))
        isempty(rel) && continue
        startswith(rel, "..") && continue
        push!(pairs, (p, rel))
    end
    return pairs
end

"""
Absolute path for `remote_path` on `host` — the controller/remote path boundary.

Use this before any controller-side join, compare, `relpath`, or rsync URI that
involves a remote path. Already-absolute paths (`/` prefix) are returned
unchanged. Paths starting with `~` are resolved **on the remote** via
[`resolve_remote_abs_path_on_host`](@ref). Returns `nothing` when resolution fails.

`~` may still be passed unquoted to remote shells ([`_remote_shell_path_word`](@ref));
do not feed tilde strings into Julia's `expanduser` / `relpath` / `abspath`.
"""
function ensure_remote_abs_path(
    host::AbstractString,
    remote_path::AbstractString,
)::Union{Nothing,String}
    path = strip(String(remote_path))
    isempty(path) && return nothing
    startswith(path, "/") && return path
    return resolve_remote_abs_path_on_host(String(host), path)
end

"""
Map remote absolute path under `remote_repo` to the same repo-relative path under `local_repo`.

`remote_abs` and `remote_repo` must already be absolute (`/` prefix). Pass
[`ensure_remote_abs_path`](@ref) results — never `~/…` (controller `abspath` would
expand tilde to the **local** home).
"""
function local_dir_from_remote_mirror(
    remote_abs::AbstractString,
    remote_repo::AbstractString,
    local_repo::AbstractString,
)::String
    ra = String(strip(String(remote_abs)))
    rr = String(strip(String(remote_repo)))
    if !(startswith(ra, "/") && startswith(rr, "/"))
        throw(ArgumentError(
            "local_dir_from_remote_mirror requires absolute remote paths; got $(repr(ra)) under $(repr(rr)). Expand ~ via ensure_remote_abs_path first.",
        ))
    end
    ra = String(abspath(ra))
    rr = String(abspath(rr))
    lr = String(abspath(local_repo))
    rel = String(relpath(ra, rr))
    startswith(rel, "..") &&
        throw(ArgumentError("remote path $(repr(ra)) is not under remote repo $(repr(rr))"))
    return String(abspath(joinpath(lr, rel)))
end

"""
Default remote layout used by `setup.jl` when paths are not overridden:
`~/basename(parent)/basename(local_project_root)` (tilde for remote-shell expansion).
"""
function default_remote_project_path(local_project_root::AbstractString)::String
    root = canonical_local_path(local_project_root)
    return joinpath("~", basename(dirname(root)), basename(root))
end

"""
Resolve the repository root path **on SSH worker hosts** for setup / git checks.

Priority:
1. `cli_override` if non-empty (e.g. `setup.jl --remote-path`)
2. `ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"]` if set (prefer an absolute path on the remote;
   `~` is OK for setup SSH shell commands; drive collect expands `~` on each host before
   `find` / rsync so controller `relpath` never sees a tilde base)
3. `default_remote_project_path(local_project_root)`

Does not force `abspath` on tilde paths so remote shells can expand `~` per host.
"""
function resolve_remote_project_root(
    local_project_root::AbstractString;
    cli_override::Union{Nothing,AbstractString}=nothing,
)::String
    if cli_override !== nothing
        s = strip(String(cli_override))
        !isempty(s) && return s
    end
    env = strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))
    !isempty(env) && return env
    return default_remote_project_path(local_project_root)
end

"""Layout path for `DISTRIBUTED_REMOTE_PROJECT_ROOT` (controller ENV / `execute!`).

`~…` stays a remote-shell layout (do not `expanduser` on the controller).
Absolute paths are [`canonical_local_path`](@ref).
"""
function remote_env_project_root(raw::AbstractString)::String
    s = strip(String(raw))
    isempty(s) && throw(ArgumentError("remote project root is empty"))
    startswith(s, "~") && return s
    return canonical_local_path(s)
end

"""Convert `https://github.com/...` clone URLs to SSH; leave other URLs unchanged.

# Examples
```jldoctest
julia> using DistSSHKit

julia> DistSSHKit.normalize_git_clone_url("https://github.com/org/App.jl.git")
"git@github.com:org/App.jl.git"
```
"""
function normalize_git_clone_url(url::AbstractString)::String
    origin_url = strip(String(url))
    m = match(r"https://github\.com/(.+)", origin_url)
    if m !== nothing
        cap = m.captures[1]
        return cap isa AbstractString ? ("git@github.com:" * String(cap)) : origin_url
    end
    return origin_url
end

"""Read `origin` from `proj_dir` and return a clone URL (HTTPS GitHub → SSH). `nothing` on failure."""
function clone_url_from_local_origin(proj_dir::AbstractString)::Union{Nothing,String}
    _host_tool_present("git") || return nothing
    resolved = canonical_local_path(proj_dir)
    try
        origin_url = strip(read(pipeline(_git_cmd(["-C", resolved, "remote", "get-url", "origin"]);
                                          stderr=devnull), String))
        isempty(origin_url) && return nothing
        return normalize_git_clone_url(origin_url)
    catch
        return nothing
    end
end

"""Join `rel` under remote repo root without expanding `~` on the local machine."""
function _join_under_remote_root(rroot::String, rel::String)::String
    if isempty(rel) || rel == "."
        return rroot
    end
    out = joinpath(rroot, rel)
    startswith(rroot, "~") && return String(out)
    return String(abspath(out))
end

"""
Absolute path to use on SSH worker hosts for `find` / rsync source / sentinel / `addprocs`.

Maps `local_abs_dir` under `local_application_repo_root` to the same relative path under the
remote repo root from [`resolve_remote_project_root`](@ref) (same default as `setup --clone`:
`~/Parent/RepoName`). Override with `DISTRIBUTED_REMOTE_PROJECT_ROOT` or `setup --remote-path`.

Paths outside the local repo root fall back to `local_abs_dir` unchanged.

Returns a **layout** path (may still start with `~`). Callers that build find lists,
rsync URIs, or `relpath` on the controller must pass the result through
[`ensure_remote_abs_path`](@ref) per host first. Prefer an absolute
`DISTRIBUTED_REMOTE_PROJECT_ROOT` when possible; `~` is sugar for remote shells.
"""
function remote_path_for_ssh_collect(
    local_abs_dir::AbstractString,
    local_application_repo_root::AbstractString,
)::String
    ld = canonical_local_path(local_abs_dir)
    root = canonical_local_path(local_application_repo_root)
    rroot = resolve_remote_project_root(root)
    if ld == root
        return rroot
    end
    rootpfx = endswith(root, '/') ? root : root * '/'
    if startswith(ld, rootpfx)
        rel = String(relpath(ld, root))
        return _join_under_remote_root(rroot, rel)
    end
    return ld
end

"""
Local absolute directories used for per-run sentinel placement and post-run rsync from SSH workers.

If `ENV["DISTRIBUTED_COLLECT_DIRS"]` is non-empty: colon-separated list (same convention as POSIX `PATH`).
Each token is `canonical_local_path(token)` when absolute, otherwise `canonical_local_path(joinpath(project_root, token))`.
Empty tokens are skipped; duplicates removed (first occurrence order preserved).

If unset or blank after trimming: a single root from [`resolve_drive_output_dir`](@ref)
(`DISTRIBUTED_OUTPUT_DIR`, else `{script_dir}/.distsshkit/drive`).

Scripts should set `DISTRIBUTED_COLLECT_DIRS` to every tree that may receive new files on workers during the run
(e.g. sweep output plus figures). Logs may stay under `DISTRIBUTED_OUTPUT_DIR` only; omit that path here if logs
should not be rsync'd.
"""
function distributed_collect_root_dirs(
    script_dir::AbstractString,
    project_root::AbstractString,
)::Vector{String}
    spec = String(strip(get(ENV, "DISTRIBUTED_COLLECT_DIRS", "")))
    repo = canonical_local_path(project_root)
    if !isempty(spec)
        out = String[]
        for chunk in split(spec, ':')
            p = String(strip(String(chunk)))
            isempty(p) && continue
            raw = String(expanduser(p))
            ap = canonical_local_path(isabspath(raw) ? raw : joinpath(repo, raw))
            push!(out, ap)
        end
        seen = Set{String}()
        uniq = String[]
        for p in out
            p in seen && continue
            push!(seen, p)
            push!(uniq, p)
        end
        if !isempty(uniq)
            return uniq
        end
    end
    return String[resolve_drive_output_dir(script_dir)]
end
