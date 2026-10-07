# SSH, where Julia is, and remote paths.

# SSH configuration

"""Build SSH options. `request_tty=false` (default) adds `RequestTTY=no`."""
function build_ssh_opts(; request_tty::Bool = false)
    custom = strip(get(ENV, "DISTRIBUTED_SSH_OPTS", ""))
    if isempty(custom)
        opts = String["-o", "BatchMode=yes"]
        if !request_tty
            push!(opts, "-o", "RequestTTY=no")
        end
        append!(
            opts, (
                "-o", "ConnectTimeout=10",
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ServerAliveInterval=60",
                "-o", "ServerAliveCountMax=10",
                "-o", "TCPKeepAlive=yes",
            )
        )
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
function ssh_opts(; request_tty::Bool = false)::Vector{String}
    return String[String(x) for x in build_ssh_opts(; request_tty = request_tty)]
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
function ssh_config_user(host::AbstractString)::Union{Nothing, String}
    h = String(strip(host))
    isempty(h) && return nothing
    try
        # -n: no stdin; -G dumps effective config (User, HostName, …).
        out = read(_ssh_cmd(["-n", ssh_opts()..., "-G", h]), String)
        for line in eachsplit(out, '\n'; keepempty = false)
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
julia> using DistSSHRun

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

"""Parse `julia --version` output (e.g. `"julia version 1.13.1"`) into a `VersionNumber`.
Returns `nothing` if the text doesn't match the expected pattern.

# Examples
```jldoctest
julia> using DistSSHRun

julia> DistSSHKit.parse_julia_version("julia version 1.13.1")
v"1.13.1"

julia> DistSSHKit.parse_julia_version("not julia") === nothing
true
```
"""
function parse_julia_version(version_output::AbstractString)::Union{Nothing, VersionNumber}
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
function get_remote_julia_version(host::String, julia_path::AbstractString)::Union{Nothing, VersionNumber}
    try
        result = read(pipeline(_ssh_cmd([ssh_opts()..., host, String(julia_path), "--version"]); stderr = devnull), String)
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
Resolve the Julia binary on this kit parent (`nothing` / `"auto"` / empty →
the running process). Explicit paths are kept as given after usability check.

Throws `ArgumentError` when the binary is missing or `--version` does not parse.
"""
function resolve_controller_julia(spec::Union{Nothing, AbstractString} = nothing)::String
    path = if _julia_spec_is_auto(spec)
        String(something(Base.julia_cmd().exec[1], ""))
    else
        String(strip(String(spec::AbstractString)))
    end
    isempty(path) && throw(ArgumentError("Julia binary not resolved on the kit parent"))
    abs = isabspath(path) ? path : abspath(path)
    try
        out = read(pipeline(Cmd([abs, "--version"]); stderr = devnull), String)
        parse_julia_version(out) === nothing && throw(
            ArgumentError(
                "kit parent Julia at $(abs) did not report a parseable --version",
            )
        )
    catch e
        e isa ArgumentError && rethrow()
        throw(ArgumentError("kit parent Julia not usable at $(abs): $(sprint(showerror, e))"))
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
        spec::Union{Nothing, AbstractString} = nothing,
    )::Union{Nothing, String}
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
        julia::Union{Nothing, AbstractString} = nothing,
        detect::Bool = true,
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
    isempty(path) && throw(
        ArgumentError(
            "run_on_host: detect=false requires julia= to a remote path (not auto)",
        )
    )
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
        argv::AbstractVector{<:AbstractString} = String[];
        julia::Union{Nothing, AbstractString} = nothing,
        detect::Bool = true,
        tty::Bool = false,
        wait::Bool = true,
    )::Base.Process
    h = String(strip(host))
    isempty(h) && throw(ArgumentError("run_on_host: host must be non-empty"))
    inner = _run_on_host_remote_sh(argv; julia = julia, detect = detect)
    args = String[ssh_opts(; request_tty = tty)...]
    tty && push!(args, "-t")
    push!(args, h, inner)
    return run(ignorestatus(_ssh_cmd(args)); wait = wait)
end

# Process-local auto-detect results (`nothing` included). Same host in
# `size!` then `drive!` / `--check` then `--instantiate` skips repeat SSH.
const _DETECT_JULIA_PATH_CACHE = Dict{String, Union{Nothing, String}}()

"""Drop cached `detect_julia_path` results (`host=nothing` → all hosts)."""
function clear_detect_julia_path_cache!(host::Union{Nothing, AbstractString} = nothing)
    if host === nothing
        empty!(_DETECT_JULIA_PATH_CACHE)
    else
        delete!(_DETECT_JULIA_PATH_CACHE, String(strip(host)))
    end
    return nothing
end

"""Detect Julia path on remote host via SSH (executable + parseable `--version`)."""
function detect_julia_path(host::String)::Union{Nothing, String}
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
            pipeline(_host_sync_remote_shell_cmd(host, "$pq --version"); stderr = devnull),
            String,
        )
        return parse_julia_version(out) !== nothing
    catch
        return false
    end
end

function _detect_julia_path_uncached(host::String)::Union{Nothing, String}
    uname_s = try
        strip(
            read(
                pipeline(_host_sync_remote_shell_cmd(host, "uname -s"); stderr = devnull),
                String,
            )
        )
    catch
        ""
    end

    if !isempty(uname_s)
        for path in remote_julia_candidates(uname_s)
            try
                result = read(
                    pipeline(
                        _host_sync_remote_shell_cmd(host, "test -x $path && echo $path");
                        stderr = devnull,
                    ), String
                )
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
        result = read(
            pipeline(
                _host_sync_remote_shell_cmd(host, "command -v julia || which julia");
                stderr = devnull,
            ), String
        )
        p = strip(result)
        isempty(p) && return nothing
        _remote_julia_reports_version(host, p) || return nothing
        return String(p)
    catch
        return nothing
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
    prefix = p[1:(slash - 1)]
    rest = p[(slash + 1):end]
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
[`remote_layout_path`](@ref) then [`resolve_remote_abs_path_on_host`](@ref).
Returns `nothing` when the remote path cannot be resolved.
"""
function resolve_host_path_abs(
        host::AbstractString,
        local_abs::AbstractString,
        local_repo_root::AbstractString,
    )::Union{Nothing, String}
    path_local = canonical_local_path(local_abs)
    h = String(strip(host))
    is_parent_host_name(h) && return path_local
    mapped = remote_layout_path(path_local, local_repo_root)
    return resolve_remote_abs_path_on_host(h, mapped)
end

"""
Absolute project root for `addprocs` / size probe on `host`.

Equivalent to [`resolve_host_path_abs`](@ref)`(host, local_project, local_project)`.
"""
function resolve_host_project_abs(
        host::AbstractString,
        local_project::AbstractString,
    )::Union{Nothing, String}
    return resolve_host_path_abs(host, local_project, local_project)
end

"""
Resolve `remote_path` to an absolute path on `host` via SSH (`cd … && pwd`).

Returns `remote_path` unchanged when it is already absolute (`/` prefix).
A `~/…` layout is expanded on the host even if the tree is not created yet.
Returns `nothing` when SSH fails, or when a non-tilde path does not exist.
"""
function resolve_remote_abs_path_on_host(host::String, remote_path::AbstractString)::Union{Nothing, String}
    path = strip(String(remote_path))
    isempty(path) && return nothing
    startswith(path, "/") && return path
    try
        inner = _remote_abs_path_resolve_shell(path)
        s = strip(read(pipeline(_ssh_cmd([ssh_opts()..., host, inner]); stderr = devnull), String))
        isempty(s) && return nothing
        return String(s)
    catch
        return nothing
    end
end

"""Remote login-shell snippet for [`get_remote_git_hash`](@ref)."""
function _remote_git_hash_inner(
        remote_repo_dir::AbstractString;
        short::Union{Nothing, Int} = nothing,
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
function get_remote_git_hash(host::String, remote_repo_dir::AbstractString; short::Union{Nothing, Int} = nothing)::Union{Nothing, String}
    try
        inner = _remote_git_hash_inner(remote_repo_dir; short = short)
        s = strip(read(pipeline(_ssh_cmd([ssh_opts()..., host, inner]); stderr = devnull), String))
        return isempty(s) ? nothing : s
    catch
        return nothing
    end
end

# Remote resource detection

"""Get total memory (GB) for a remote host via SSH."""
function get_remote_total_gb(host::String)
    try
        s = strip(
            read(
                pipeline(
                    _ssh_cmd(
                        [
                            ssh_opts()..., host,
                            "sysctl -n hw.memsize 2>/dev/null || awk '/MemTotal/{print \$2*1024}' /proc/meminfo 2>/dev/null",
                        ]
                    );
                    stderr = devnull
                ), String
            )
        )
        isempty(s) && return nothing
        return parse(Float64, s) / 1024^3
    catch end
    return nothing
end

"""Get CPU core count for a remote host via SSH."""
function get_remote_nproc(host::String)
    try
        s = strip(
            read(
                pipeline(
                    _ssh_cmd(
                        [
                            ssh_opts()..., host,
                            "sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null",
                        ]
                    ); stderr = devnull
                ), String
            )
        )
        isempty(s) && return nothing
        return parse(Int, s)
    catch end
    return nothing
end

"""
Absolute path for `remote_path` on `host` — the kit-parent/remote path boundary.

Use this before any kit-parent-side join, compare, `relpath`, or rsync URI that
involves a remote path. Already-absolute paths (`/` prefix) are returned
unchanged. Paths starting with `~` are resolved **on the remote** via
[`resolve_remote_abs_path_on_host`](@ref). Returns `nothing` when resolution fails.

`~` may still be passed unquoted to remote shells (`_remote_shell_path_word`);
do not feed tilde strings into Julia's `expanduser` / `relpath` / `abspath`.
"""
function ensure_remote_abs_path(
        host::AbstractString,
        remote_path::AbstractString,
    )::Union{Nothing, String}
    path = strip(String(remote_path))
    isempty(path) && return nothing
    startswith(path, "/") && return path
    return resolve_remote_abs_path_on_host(String(host), path)
end

"""
Map remote absolute path under `remote_repo` to the same repo-relative path under `local_repo`.

`remote_abs` and `remote_repo` must already be absolute (`/` prefix). Pass
[`ensure_remote_abs_path`](@ref) results — never `~/…` (kit parent `abspath` would
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
        throw(
            ArgumentError(
                "local_dir_from_remote_mirror requires absolute remote paths; got $(repr(ra)) under $(repr(rr)). Expand ~ via ensure_remote_abs_path first.",
            )
        )
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

"""Remote tree root for `local_tree` (override, else `DISTRIBUTED_REMOTE_PROJECT_ROOT`, else the default layout)."""
function _remote_tree_root(
        local_tree::AbstractString;
        cli_override::Union{Nothing, AbstractString} = nothing,
    )::String
    if cli_override !== nothing
        s = strip(String(cli_override))
        !isempty(s) && return s
    end
    env = strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))
    !isempty(env) && return env
    return default_remote_project_path(local_tree)
end

"""
Directory on the worker that receives `setup --rsync` of [`resolve_pkg_env`](@ref) `env_dir`.

An override (`--remote-path` / `DISTRIBUTED_REMOTE_PROJECT_ROOT`) is this tree
root, not the member directory.
"""
function remote_deploy_root(
        local_project_root::AbstractString;
        cli_override::Union{Nothing, AbstractString} = nothing,
    )::String
    env = resolve_pkg_env(local_project_root)
    return _remote_tree_root(env.env_dir; cli_override = cli_override)
end

"""
Worker `--project` path for `local_project_root`.

Same override rules as [`remote_deploy_root`](@ref). When the Manifest lives in
a parent of the member, this is `deploy_root` plus that relative path.
A single-project tree returns the deploy root unchanged. Does not `abspath`
tilde paths.
"""
function resolve_remote_project_root(
        local_project_root::AbstractString;
        cli_override::Union{Nothing, AbstractString} = nothing,
    )::String
    env = resolve_pkg_env(local_project_root)
    deploy = _remote_tree_root(env.env_dir; cli_override = cli_override)
    rel = julia_project_rel(env)
    return rel == "." ? deploy : _join_under_remote_root(deploy, rel)
end

"""
Directory `git clone` should create.

When the git work tree root is [`resolve_pkg_env`](@ref) `env_dir`, this is
[`remote_deploy_root`](@ref). When `env_dir` sits under that work tree, the
destination is the ancestor of the deploy root by the same relative path, so
the Manifest directory still lands on the deploy root. No git work tree keeps
[`resolve_remote_project_root`](@ref) (the member).
"""
function remote_git_clone_dest(
        local_project_root::AbstractString;
        cli_override::Union{Nothing, AbstractString} = nothing,
    )::String
    env = resolve_pkg_env(local_project_root)
    deploy = _remote_tree_root(env.env_dir; cli_override = cli_override)
    top = git_work_tree(env.project_dir)
    top isa String || return resolve_remote_project_root(local_project_root; cli_override = cli_override)
    # `git rev-parse` may return `/private/var/...` while Julia's temp path is `/var/...`.
    env_root = canonical_local_path(realpath(env.env_dir))
    top_root = canonical_local_path(realpath(top))
    _path_is_under(env_root, top_root) ||
        return resolve_remote_project_root(local_project_root; cli_override = cli_override)
    return _remote_ancestor(deploy, relpath(env_root, top_root))
end

"""
Path `setup --delete` removes.

When the git work tree contains `env_dir` and the deploy path ends with that
relative path, this is [`remote_git_clone_dest`](@ref), so a clone that landed
above the deploy root is removed with `.git`. An override that cannot express
that parent, or no git work tree, removes [`remote_deploy_root`](@ref).
"""
function remote_delete_root(
        local_project_root::AbstractString;
        cli_override::Union{Nothing, AbstractString} = nothing,
    )::String
    env = resolve_pkg_env(local_project_root)
    deploy = _remote_tree_root(env.env_dir; cli_override = cli_override)
    top = git_work_tree(env.project_dir)
    top isa String || return deploy
    env_root = canonical_local_path(realpath(env.env_dir))
    top_root = canonical_local_path(realpath(top))
    _path_is_under(env_root, top_root) || return deploy
    mapped = _remote_ancestor_or_nothing(deploy, relpath(env_root, top_root))
    return mapped === nothing ? deploy : mapped
end

"""Drop `rel` from the end of a remote layout path. `rel` of `.` returns `remote_path`."""
function _remote_ancestor(remote_path::AbstractString, rel::AbstractString)::String
    mapped = _remote_ancestor_or_nothing(remote_path, rel)
    mapped === nothing && throw(
        ArgumentError(
            "Remote path $remote_path does not end with $rel, so clone cannot keep the Manifest directory there.",
        ),
    )
    return mapped
end

"""`_remote_ancestor`, or `nothing` when `remote_path` does not end with `rel`."""
function _remote_ancestor_or_nothing(
        remote_path::AbstractString,
        rel::AbstractString,
    )::Union{Nothing, String}
    rel == "." && return String(remote_path)
    p = String(remote_path)
    for part in reverse(split(String(rel), '/'))
        (isempty(part) || part == ".") && continue
        part == ".." && return nothing
        basename(p) == part || return nothing
        parent = dirname(p)
        parent == p && return nothing
        p = parent
    end
    return p
end

"""Layout path for `DISTRIBUTED_REMOTE_PROJECT_ROOT` (kit parent ENV / `execute!`).

`~…` stays a remote-shell layout (do not `expanduser` on the kit parent).
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
julia> using DistSSHRun

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
function clone_url_from_local_origin(proj_dir::AbstractString)::Union{Nothing, String}
    _host_tool_present("git") || return nothing
    resolved = canonical_local_path(proj_dir)
    try
        origin_url = strip(
            read(
                pipeline(
                    _git_cmd(["-C", resolved, "remote", "get-url", "origin"]);
                    stderr = devnull
                ), String
            )
        )
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
    remote_layout_path(local_abs_dir, local_application_repo_root) -> String

Layout path, not a path resolved on the host. It may start with `~`.
Do not `expanduser` it on this machine. Pass it through
[`ensure_remote_abs_path`](@ref) before using it on a host.

A path outside `local_application_repo_root` is returned unchanged.
That result is the local absolute path, not a remote path.

A path under the repo root is the same relative path under
[`resolve_remote_project_root`](@ref). The default root matches
`setup --clone` (`~/Parent/RepoName`). Override with
`DISTRIBUTED_REMOTE_PROJECT_ROOT` or `setup --remote-path`.
"""
function remote_layout_path(
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

"""Julia argv for `DISTSSHKIT_TEST_SSH` / `.jl` rsync doubles (`--compile=min`)."""
function _test_double_julia_argv(script::AbstractString)::Vector{String}
    julia = joinpath(Sys.BINDIR, Base.julia_exename())
    return [julia, "--startup-file=no", "--compile=min", abspath(script)]
end

function _host_sync_remote_shell_cmd(host::String, remote_script::String)::Cmd
    custom = strip(get(ENV, "DISTSSHKIT_TEST_SSH", ""))
    if !isempty(custom)
        return Cmd(vcat(_test_double_julia_argv(custom), [host, remote_script]))
    end
    # `-n`: do not forward kit stdin (juliaup/git must not wait on a TTY pipe).
    return _ssh_cmd(["-n", ssh_opts()..., host, remote_script])
end


"""`git rev-parse --show-toplevel` for `proj_dir`, or `nothing` when it is not a work tree."""
function git_work_tree(proj_dir::AbstractString)::Union{Nothing, String}
    _host_tool_present("git") || return nothing
    resolved = canonical_local_path(proj_dir)
    try
        s = strip(
            read(
                pipeline(_git_cmd(["-C", resolved, "rev-parse", "--show-toplevel"]); stderr = devnull),
                String,
            )
        )
        return isempty(s) ? nothing : canonical_local_path(s)
    catch
        return nothing
    end
end
