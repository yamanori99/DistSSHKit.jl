# execute! — one seam over `go!` / `drive!` for callers that pick the kind at runtime
# (the queue layer; see https://github.com/yamanori99/DistSSHKit.jl/issues/129).
# Thin wrapper only: `go!` / `drive!` / `src/cli/*` are untouched.
# `detached=true` spawns `julia -m DistSSHKit go|drive` and returns [`KitProcess`](@ref).

const _EXECUTE_DETACHED_KW = Set{Symbol}((
    :quiet,
    :verbosity,
    :yes,
    :remote,
    :hosts_file,
    :log_dir,
    :enable_log,
    :package,
    :require_all_hosts,
    :skip_hash_check,
    :stdout,
    :stderr,
    :job_id,
))
const _EXECUTE_DETACHED_DRIVE_ONLY = (
    :log_dir,
    :enable_log,
    :package,
    :require_all_hosts,
    :skip_hash_check,
)
const _EXECUTE_DETACHED_ENV_SKIP = Set((
    "JULIA_LOAD_PATH",
    "DISTSSHKIT_CLI_SUBCOMMAND_DONE",
    "DIST_SSH_KIT_CLI_INCLUDE",
))
# Named `execute!` kwargs (not in `_EXECUTE_DETACHED_KW`; they are not `kwargs...`).
const _EXECUTE_DETACHED_NAMED = (
    :output_dir,
    :args,
    :project,
    :sync,
    :julia,
    :detached,
)

"""
    execute_detached_accepts(kw; kind) -> Bool

Whether `execute!(kind, ...; detached=true)` accepts keyword `kw`.
Uses the same tables as the detached throw path, plus the named parameters
(`output_dir`, `args`, `project`, `sync`, `julia`, `detached`).
"""
function execute_detached_accepts(kw::Symbol; kind::Symbol)::Bool
    kind in (:go, :drive) || throw(ArgumentError(
        "execute! kind must be :go or :drive, got $(repr(kind))",
    ))
    kw in _EXECUTE_DETACHED_NAMED && return true
    kw in _EXECUTE_DETACHED_KW || return false
    kind === :go && return !(kw in _EXECUTE_DETACHED_DRIVE_ONLY)
    return true
end

"""
Handle to a detached [`execute!`](@ref) child (`detached=true`).

`process` is the `julia -m DistSSHKit go|drive` subprocess.
`output_dir` / `log_dir` are resolved in the parent before spawn so they match
the child (`log_dir` is `nothing` for `:go`, matching [`kit_run_result`](@ref)
on [`GoResult`](@ref)). Convert with `wait`.
"""
struct KitProcess
    process::Base.Process
    kind::Symbol
    output_dir::Union{Nothing,String}
    log_dir::Union{Nothing,String}
    stdout_owned::Union{Nothing,IO}
    stderr_owned::Union{Nothing,IO}
end

function KitProcess(
    process::Base.Process;
    kind::Symbol,
    output_dir::Union{Nothing,AbstractString}=nothing,
    log_dir::Union{Nothing,AbstractString}=nothing,
    stdout_owned::Union{Nothing,IO}=nothing,
    stderr_owned::Union{Nothing,IO}=nothing,
)
    kind in (:go, :drive) || throw(ArgumentError("KitProcess kind must be :go or :drive, got $(repr(kind))"))
    return KitProcess(
        process, kind, _optional_path(output_dir), _optional_path(log_dir),
        stdout_owned, stderr_owned,
    )
end

function _close_owned_stdio!(kp::KitProcess)
    for io in (kp.stdout_owned, kp.stderr_owned)
        io === nothing && continue
        try
            close(io)
        catch
        end
    end
    return nothing
end

"""
    wait(kp::KitProcess; timeout=nothing) -> KitRunResult

Block until the detached child exits, then return a [`KitRunResult`](@ref).

`timeout` is wall-clock seconds until the **child process** exits (not the
drive worker heartbeat). `nothing` waits forever. On timeout the child is
left running: `failed_step` is `"hung"`, `exit_code` is `124`, and owned
stdio stays open. Call [`terminate!`](@ref) if the hang is fatal.

If the child wrote `kit.result`, that file is the source of truth (including
`failed_step` from `go!`). Otherwise `failed_step` is `"go"` / `"drive"` on a
non-zero exit — the parent cannot recover a more specific in-process step name.

Best-effort: remove `kit.pid` if it still names this child (pid captured
before `wait` on the OS process; after reap `getpid` can throw ESRCH).
Not on a hung timeout.
"""
function Base.wait(
    kp::KitProcess;
    timeout::Union{Nothing,Real}=nothing,
)::KitRunResult
    timeout !== nothing && timeout < 0 && throw(ArgumentError(
        "wait timeout must be ≥ 0, got $timeout",
    ))
    child_pid = try
        Int(getpid(kp.process))
    catch
        nothing
    end
    if timeout !== nothing && process_running(kp.process)
        t0 = time()
        while process_running(kp.process) && (time() - t0) < Float64(timeout)
            sleep(0.05)
        end
        if process_running(kp.process)
            return KitRunResult(false, kp.kind, kp.output_dir, kp.log_dir, "hung", 124)
        end
    end
    try
        wait(kp.process)
        recovered = kp.output_dir === nothing ? nothing : kit_result_from_dir(kp.output_dir)
        child_pid !== nothing && _remove_kit_pid_file(child_pid, kp.output_dir, kp.log_dir)
        recovered !== nothing && return recovered
        code = Int(something(kp.process.exitcode, 1))
        ok = code == 0
        return KitRunResult(
            ok,
            kp.kind,
            kp.output_dir,
            kp.log_dir,
            ok ? nothing : String(kp.kind),
            code,
        )
    finally
        _close_owned_stdio!(kp)
    end
end

"""
    execute!(kind, script, tokens=String[]; output_dir=nothing, args=String[], project=pwd(), sync=nothing, julia=nothing, detached=false, kwargs...) -> KitRunResult or KitProcess

One seam over [`go!`](@ref) / [`drive!`](@ref) for callers that pick the kind
at runtime (`kind ∈ (:go, :drive)`), returning the shared [`KitRunResult`](@ref)
instead of `GoResult` / `DriveResult`.

```julia
execute!(:go, "job.jl", ["parenthost:2"]; args=["8"])
execute!(:drive, "job.jl", ["parenthost:2"]; args=["8"])
wait(execute!(:go, "job.jl", ["parenthost:1"]; detached=true, args=["8"]))
```

`output_dir`, `args`, `project`, `sync`, `julia` are the keywords [`go!`](@ref)
and [`drive!`](@ref) already share. With `detached=false` (default), any other
keyword (`remote`, `hosts_file`, `quiet`, `verbosity`, `yes`, `collect_spec`,
`path_anchor`, `skip_hash_check`, `require_all_hosts`, `plan`, …) is forwarded
verbatim to the chosen function.

`detached=true` spawns `julia -m DistSSHKit go|drive` and returns a
[`KitProcess`](@ref). Keywords are then an allow-list (unknown names throw):
`output_dir`, `args`, `project`, `sync`, `julia`, `quiet`, `verbosity`, `yes`,
`remote`, `hosts_file`, `job_id`, and drive-only `log_dir`, `enable_log`,
`package`, `require_all_hosts`, `skip_hash_check`. `yes` must be `true` (the
default): an unattended child cannot answer a prompt. Child stdio defaults to
`kit.out` / `kit.err` in `output_dir`. Pass `stdout` / `stderr` (`IO`) to
override; `stdout=stdout` inherits the parent. Parent `redirect_stdout` does
not apply to the subprocess.

`job_id`, if given, is passed to the child as `DISTSSHKIT_JOB_ID`, which
adds `job=<id>` to every `progress:` log line. `DISTSSHKIT_PROGRESS=1` is
`--progress` verbosity, not a watcher; read lines with
[`parse_progress_line`](@ref) / [`kit_progress_latest`](@ref).
Omitted entirely when unset.
"""
function execute!(
    kind::Symbol,
    script::AbstractString,
    tokens::AbstractVector{<:AbstractString}=String[];
    output_dir::Union{Nothing,AbstractString}=nothing,
    args::AbstractVector{<:AbstractString}=String[],
    project::AbstractString=pwd(),
    sync::Union{Symbol,Bool,Nothing}=nothing,
    julia::Union{Nothing,AbstractString}=nothing,
    detached::Bool=false,
    kwargs...,
)
    kind in (:go, :drive) || throw(ArgumentError("execute! kind must be :go or :drive, got $(repr(kind))"))
    if detached
        return _execute_detached!(
            kind,
            script,
            tokens;
            output_dir=output_dir,
            args=args,
            project=project,
            sync=sync,
            julia=julia,
            kwargs...,
        )
    end
    result = if kind === :go
        go!(
            script,
            tokens;
            output_dir=output_dir,
            args=args,
            project=project,
            sync=sync,
            julia=julia,
            kwargs...,
        )
    else
        drive!(
            script,
            tokens;
            output_dir=output_dir,
            args=args,
            project=project,
            sync=sync,
            julia=julia,
            kwargs...,
        )
    end
    return kit_run_result(result)
end

function _execute_detached!(
    kind::Symbol,
    script::AbstractString,
    tokens::AbstractVector{<:AbstractString};
    output_dir::Union{Nothing,AbstractString},
    args::AbstractVector{<:AbstractString},
    project::AbstractString,
    sync::Union{Symbol,Bool,Nothing},
    julia::Union{Nothing,AbstractString},
    kwargs...,
)::KitProcess
    for k in keys(kwargs)
        k in _EXECUTE_DETACHED_KW || throw(ArgumentError(
            "execute!(...; detached=true) does not accept keyword $(repr(k))",
        ))
    end
    if kind === :go
        for k in _EXECUTE_DETACHED_DRIVE_ONLY
            haskey(kwargs, k) && throw(ArgumentError(
                "execute!(:go, ...; detached=true) does not accept keyword $(repr(k))",
            ))
        end
    end
    yes = get(kwargs, :yes, true)
    yes === true || throw(ArgumentError("execute!(...; detached=true) requires yes=true"))
    quiet = get(kwargs, :quiet, false)
    quiet isa Bool || throw(ArgumentError("quiet must be a Bool, got $(repr(quiet))"))
    verbosity = get(kwargs, :verbosity, nothing)
    if verbosity !== nothing && !(verbosity isa Symbol)
        throw(ArgumentError("verbosity must be a Symbol or nothing, got $(repr(verbosity))"))
    end
    remote = get(kwargs, :remote, nothing)
    hosts_file = get(kwargs, :hosts_file, nothing)
    log_dir = get(kwargs, :log_dir, nothing)
    enable_log = get(kwargs, :enable_log, true)
    package = get(kwargs, :package, nothing)
    require_all_hosts = get(kwargs, :require_all_hosts, false)
    skip_hash_check = get(kwargs, :skip_hash_check, true)

    proj = canonical_local_path(project)
    script_path = canonical_local_path(script)
    script_dir = dirname(script_path)
    resolved_output, resolved_log = _execute_detached_dirs(
        kind,
        script_dir,
        proj,
        script_path,
        output_dir,
        log_dir,
        enable_log,
    )
    argv = _execute_detached_argv(
        kind,
        script_path,
        tokens,
        args;
        output_dir=resolved_output,
        log_dir=resolved_log,
        sync=sync,
        julia=julia,
        quiet=quiet,
        verbosity=verbosity,
        hosts_file=hosts_file,
        enable_log=enable_log,
        package=package,
        require_all_hosts=require_all_hosts,
        skip_hash_check=skip_hash_check,
    )
    extra = Dict{String,String}("DISTRIBUTED_PROJECT_ROOT" => proj)
    if remote !== nothing && !isempty(strip(String(remote)))
        extra["DISTRIBUTED_REMOTE_PROJECT_ROOT"] = canonical_local_path(String(remote))
    end
    job_id = get(kwargs, :job_id, nothing)
    if job_id !== nothing && !isempty(strip(String(job_id)))
        extra["DISTSSHKIT_JOB_ID"] = _parse_kit_job_id(String(job_id))
    end
    env = _execute_detached_env(extra)
    julia_bin = resolve_controller_julia(julia)
    kit_proj = pkgdir(DistSSHKit)
    kit_proj === nothing && throw(ArgumentError("pkgdir(DistSSHKit) is nothing; cannot spawn -m DistSSHKit"))
    cmd = Cmd(String[
        julia_bin,
        "--startup-file=no",
        "--project=$(kit_proj)",
        "-m",
        "DistSSHKit",
        argv...,
    ])
    child = ignorestatus(setenv(cmd, env))
    stdio_out, stdio_err, owned_out, owned_err = _execute_detached_stdio(kwargs, resolved_output)
    proc = try
        run(pipeline(child; stdout=stdio_out, stderr=stdio_err); wait=false)
    catch
        for io in (owned_out, owned_err)
            io === nothing || close(io)
        end
        rethrow()
    end
    _write_kit_pid_file(
        getpid(proc), resolved_output, resolved_log;
        job_id=get(extra, "DISTSSHKIT_JOB_ID", nothing),
    )
    return KitProcess(
        proc;
        kind=kind,
        output_dir=resolved_output,
        log_dir=resolved_log,
        stdout_owned=owned_out,
        stderr_owned=owned_err,
    )
end

"""Open `kit.out` / `kit.err` under `output_dir` when `stdout` / `stderr` are omitted."""
function _execute_detached_stdio(kwargs, output_dir::AbstractString)
    stdio_out = get(kwargs, :stdout, nothing)
    stdio_err = get(kwargs, :stderr, nothing)
    owned_out = nothing
    owned_err = nothing
    if stdio_out === nothing
        mkpath(output_dir)
        owned_out = open(joinpath(output_dir, "kit.out"), "w")
        stdio_out = owned_out
    end
    if stdio_err === nothing
        mkpath(output_dir)
        owned_err = open(joinpath(output_dir, "kit.err"), "w")
        stdio_err = owned_err
    end
    return stdio_out, stdio_err, owned_out, owned_err
end

"""
Best-effort `kit.pid` drop in `output_dir` (and `log_dir` if distinct) holding
the detached child's OS pid as plain text.

Lets a caller that lost its in-memory [`KitProcess`](@ref) (e.g. a queue
service restarted while a job was running) re-check liveness later via
`kill(pid, 0)` / equivalent, without any other change to `execute!`. Never
throws: a failure here must not fail the spawn that already happened.

The child removes the file in `go!` / `drive!` `finally` when it still names
this pid (same rule as `.kit.lock`). [`wait`](@ref) does the same as backup
when the caller still has a [`KitProcess`](@ref). SIGKILL / crash can leave
the file; a reused pid can then look alive.
"""
function _kit_sidecar_dirs(
    output_dir::AbstractString,
    log_dir::Union{Nothing,AbstractString},
)
    log_dir === nothing || log_dir == output_dir ? (output_dir,) : (output_dir, log_dir)
end

function _write_kit_pid_file(
    pid::Integer,
    output_dir::AbstractString,
    log_dir::Union{Nothing,AbstractString};
    job_id::Union{Nothing,AbstractString}=nothing,
)
    dirs = _kit_sidecar_dirs(output_dir, log_dir)
    for d in dirs
        try
            mkpath(d) # child creates it too, but may not have raced ahead of us yet
            write(joinpath(d, "kit.pid"), string(pid))
            if job_id !== nothing && !isempty(strip(String(job_id)))
                write(joinpath(d, "kit.job"), strip(String(job_id)))
            end
        catch
            # best-effort only
        end
    end
    return nothing
end

function _write_kit_text_file!(
    name::AbstractString,
    body::AbstractString,
    output_dir::AbstractString,
    log_dir::Union{Nothing,AbstractString},
)
    for d in _kit_sidecar_dirs(output_dir, log_dir)
        try
            mkpath(d)
            write(joinpath(d, name), body)
        catch
        end
    end
    return nothing
end

"""Best-effort host list for [`terminate_run!`](@ref) (SSH names, one per line)."""
function _write_kit_hosts_file(
    hosts::AbstractVector{<:AbstractString},
    output_dir::AbstractString,
    log_dir::Union{Nothing,AbstractString},
)
    isempty(hosts) && return nothing
    names = unique!(String[String(h) for h in hosts])
    body = sprint() do io
        for h in names
            println(io, h)
        end
    end
    _write_kit_text_file!("kit.hosts", body, output_dir, log_dir)
    return nothing
end

function _read_kit_text_file(output_dir::AbstractString, name::AbstractString)::Union{Nothing,String}
    path = joinpath(String(output_dir), name)
    isfile(path) || return nothing
    s = try
        strip(read(path, String))
    catch
        return nothing
    end
    return isempty(s) ? nothing : s
end

function _read_kit_hosts(output_dir::AbstractString)::Vector{String}
    raw = _read_kit_text_file(output_dir, "kit.hosts")
    raw === nothing && return String[]
    return String[strip(line) for line in split(raw, '\n') if !isempty(strip(line))]
end

function _reap_tagged_workers!(job_id::Union{Nothing,AbstractString}, hosts::AbstractVector{<:AbstractString})
    job_id === nothing && return nothing
    id = String(job_id)
    _pkill_local_tagged_workers!(id)
    for host in hosts
        _pkill_remote_tagged_workers!(String(host), id)
    end
    return nothing
end

function _signal_and_wait_pid!(pid::Integer, grace::Real)
    pid <= 0 && return nothing
    kit_pid_alive(pid) || return nothing
    Sys.isunix() || return nothing
    try
        ccall(:kill, Cint, (Cint, Cint), Cint(pid), Cint(15))
    catch
    end
    t0 = time()
    while kit_pid_alive(pid) && (time() - t0) < Float64(grace)
        sleep(0.05)
    end
    if kit_pid_alive(pid)
        try
            ccall(:kill, Cint, (Cint, Cint), Cint(pid), Cint(9))
        catch
        end
        t1 = time()
        while kit_pid_alive(pid) && (time() - t1) < 1.0
            sleep(0.05)
        end
    end
    return nothing
end

"""Remove `kit.pid` in the same dirs as [`_write_kit_pid_file`](@ref), only if it still names `pid`."""
function _remove_kit_pid_file(
    pid::Integer,
    output_dir::Union{Nothing,AbstractString},
    log_dir::Union{Nothing,AbstractString},
)
    output_dir === nothing && return nothing
    dirs = log_dir === nothing || log_dir == output_dir ? (output_dir,) : (output_dir, log_dir)
    want = string(pid)
    for d in dirs
        path = joinpath(d, "kit.pid")
        try
            if isfile(path) && strip(read(path, String)) == want
                rm(path; force=true)
            end
        catch
            # best-effort only
        end
    end
    return nothing
end

"""Best-effort `kit.result` TOML next to `kit.pid`. Never throws."""
function _write_kit_result_file(result::KitRunResult)
    output_dir = result.output_dir
    output_dir === nothing && return nothing
    dirs = result.log_dir === nothing || result.log_dir == output_dir ?
        (output_dir,) : (output_dir, result.log_dir)
    data = Dict{String,Any}(
        "ok" => result.ok,
        "kind" => String(result.kind),
        "exit_code" => result.exit_code,
        "output_dir" => String(output_dir),
    )
    result.failed_step !== nothing && (data["failed_step"] = result.failed_step)
    result.log_dir !== nothing && (data["log_dir"] = result.log_dir)
    for d in dirs
        try
            mkpath(d)
            dest = joinpath(d, "kit.result")
            tmp = dest * ".tmp"
            open(tmp, "w") do io
                TOML.print(io, data)
            end
            mv(tmp, dest; force=true)
        catch
            # best-effort only
        end
    end
    return nothing
end

"""
    kit_result_from_dir(output_dir) -> Union{Nothing,KitRunResult}

Read `output_dir/kit.result` written by a finished `go` / `drive` child.
`nothing` when the file is missing or unreadable (still running, or a hard death).
"""
function kit_result_from_dir(output_dir::AbstractString)::Union{Nothing,KitRunResult}
    path = joinpath(canonical_local_path(output_dir), "kit.result")
    isfile(path) || return nothing
    try
        raw = TOML.parsefile(path)
        ok = raw["ok"]
        ok isa Bool || return nothing
        kind_s = raw["kind"]
        kind_s isa AbstractString || return nothing
        ks = String(kind_s)
        (ks == "go" || ks == "drive" || ks == "pipeline") || return nothing
        kind = Symbol(ks)
        code = raw["exit_code"]
        code isa Integer || return nothing
        od = get(raw, "output_dir", nothing)
        od_s = od isa AbstractString ? String(od) : nothing
        ld = get(raw, "log_dir", nothing)
        ld_s = ld isa AbstractString ? String(ld) : nothing
        fs = get(raw, "failed_step", nothing)
        fs_s = fs isa AbstractString ? String(fs) : nothing
        return KitRunResult(ok, kind, od_s, ld_s, fs_s, Int(code))
    catch
        return nothing
    end
end

"""
    allocate_output_dir(kind, script; project=pwd(), job_id=nothing) -> String

Create a unique output directory for a later detached [`execute!`](@ref)
and return its path. `kind` is `:go` or `:drive` (the same values as
`execute!`). The directory is created; pass it as `output_dir=`.

Layout is `<project>/.distsshkit/<kind>/<script-stem>_<UTC-stamp>/`. When
`job_id` is set it is appended after the stamp (same charset as
[`execute!`](@ref) `job_id`). If that path already exists, a nanosecond
suffix is added so two allocations in the same second do not share a
directory.

This is the unique sibling of the defaults used when `output_dir` is
omitted: go uses the same `.distsshkit/go/` tree, while drive's omitted
default remains `../results` next to the script (shared). Queue should
call this instead of reusing that shared folder.
"""
function allocate_output_dir(
    kind::Symbol,
    script::AbstractString;
    project::AbstractString=pwd(),
    job_id::Union{Nothing,AbstractString}=nothing,
)::String
    kind in (:go, :drive) || throw(
        ArgumentError("allocate_output_dir: kind must be :go or :drive, got $(repr(kind))"),
    )
    proj = canonical_local_path(project)
    isdir(proj) || throw(ArgumentError("allocate_output_dir: project is not a directory: $proj"))
    stem = splitext(basename(String(script)))[1]
    isempty(stem) && throw(ArgumentError("allocate_output_dir: empty script basename"))
    stamp = Dates.format(Dates.now(Dates.UTC), dateformat"yyyymmddTHHMMSS") * "Z"
    leaf = if job_id !== nothing && !isempty(strip(String(job_id)))
        "$(stem)_$(stamp)_$(_parse_kit_job_id(String(job_id)))"
    else
        "$(stem)_$(stamp)"
    end
    dir = joinpath(proj, ".distsshkit", String(kind), leaf)
    if ispath(dir)
        dir = dir * "-" * string(time_ns())
    end
    mkpath(dir)
    return dir
end

function _execute_detached_dirs(
    kind::Symbol,
    script_dir::AbstractString,
    project::AbstractString,
    script_path::AbstractString,
    output_dir::Union{Nothing,AbstractString},
    log_dir::Union{Nothing,AbstractString},
    enable_log,
)::Tuple{String,Union{Nothing,String}}
    resolved_output = if output_dir !== nothing
        canonical_local_path(output_dir)
    elseif kind === :go
        _go_batch_output_dir(project, script_path)
    else
        resolve_drive_output_dir(script_dir)
    end
    resolved_log = if kind === :go || enable_log === false
        nothing
    elseif log_dir !== nothing
        canonical_local_path(String(log_dir))
    elseif output_dir !== nothing
        resolved_output
    else
        canonical_local_path(resolve_drive_log_dir(nothing, script_dir))
    end
    return resolved_output, resolved_log
end

function _execute_detached_argv(
    kind::Symbol,
    script_path::AbstractString,
    tokens::AbstractVector{<:AbstractString},
    args::AbstractVector{<:AbstractString};
    output_dir::AbstractString,
    log_dir::Union{Nothing,AbstractString},
    sync::Union{Symbol,Bool,Nothing},
    julia::Union{Nothing,AbstractString},
    quiet::Bool,
    verbosity,
    hosts_file,
    enable_log,
    package,
    require_all_hosts,
    skip_hash_check,
)::Vector{String}
    argv = String[String(kind)]
    push!(argv, "-y")
    if verbosity === nothing
        quiet && push!(argv, "-q")
    elseif verbosity === :quiet
        push!(argv, "-q")
    elseif verbosity === :progress
        push!(argv, "--progress")
    elseif verbosity === :verbose
        push!(argv, "--verbose")
    else
        throw(ArgumentError("verbosity must be :quiet, :progress, or :verbose, got $(repr(verbosity))"))
    end
    push!(argv, "--output-dir", String(output_dir))
    if sync === :sync
        push!(argv, "--sync")
    elseif sync === :rsync
        push!(argv, "--rsync")
    elseif sync === false && kind === :go
        push!(argv, "--skip-sync")
    elseif sync !== nothing && sync !== false
        throw(ArgumentError("sync must be nothing, false, :sync, or :rsync, got $(repr(sync))"))
    end
    if !_julia_spec_is_auto(julia)
        push!(argv, "--julia", String(strip(String(julia))))
    end
    if hosts_file !== nothing && !isempty(strip(String(hosts_file)))
        push!(argv, "--hosts-file", canonical_local_path(String(hosts_file)))
    end
    if kind === :drive
        enable_log === false && push!(argv, "--no-log")
        if log_dir !== nothing
            push!(argv, "--log-dir", String(log_dir))
        end
        if package !== nothing && !isempty(strip(String(package)))
            push!(argv, "--package", String(package))
        end
        require_all_hosts === true && push!(argv, "--require-all-hosts")
        skip_hash_check === false && push!(argv, "--require-git")
    end
    for tok in tokens
        push!(argv, String(tok))
    end
    push!(argv, String(script_path))
    for a in args
        push!(argv, String(a))
    end
    return argv
end

function _execute_detached_env(extra::AbstractDict{<:AbstractString,<:AbstractString})::Dict{String,String}
    env = Dict{String,String}(
        String(k) => String(v) for (k, v) in ENV if !isempty(v) && !(String(k) in _EXECUTE_DETACHED_ENV_SKIP)
    )
    env["DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL"] = "1"
    for (k, v) in extra
        env[String(k)] = String(v)
    end
    return env
end

"""
    terminate!(kp::KitProcess; grace=10) -> KitRunResult

Stop a detached run. SIGTERM the child, wait up to `grace` seconds for its
own `rmprocs` path, then SIGKILL if needed. Then `pkill` only processes
tagged with this run's `job_id` (from `kit.job`), never `julia.*--worker`.
Without `job_id`, only the child is signaled.
"""
function terminate!(kp::KitProcess; grace::Real=10)::KitRunResult
    grace >= 0 || throw(ArgumentError("grace must be ≥ 0, got $grace"))
    if process_running(kp.process)
        try
            kill(kp.process, Base.SIGTERM)
        catch
        end
        t0 = time()
        while process_running(kp.process) && (time() - t0) < Float64(grace)
            sleep(0.05)
        end
        if process_running(kp.process)
            try
                kill(kp.process, Base.SIGKILL)
            catch
            end
        end
    end
    out = kp.output_dir
    job_id = out === nothing ? nothing : _read_kit_text_file(out, "kit.job")
    hosts = out === nothing ? String[] : _read_kit_hosts(out)
    _reap_tagged_workers!(job_id, hosts)
    return wait(kp)
end

"""
    terminate_run!(output_dir; grace=10, log_dir=nothing, kind=:go) -> KitRunResult

Like [`terminate!`](@ref) after losing [`KitProcess`](@ref): read `kit.pid` /
`kit.job` / `kit.hosts` under `output_dir`. `kind` is only used when
`kit.result` is missing.
"""
function terminate_run!(
    output_dir::AbstractString;
    grace::Real=10,
    log_dir::Union{Nothing,AbstractString}=nothing,
    kind::Symbol=:go,
)::KitRunResult
    grace >= 0 || throw(ArgumentError("grace must be ≥ 0, got $grace"))
    kind in (:go, :drive) || throw(ArgumentError(
        "execute! kind must be :go or :drive, got $(repr(kind))",
    ))
    d = canonical_local_path(output_dir)
    pid_s = _read_kit_text_file(d, "kit.pid")
    pid = pid_s === nothing ? nothing : tryparse(Int, pid_s)
    pid !== nothing && _signal_and_wait_pid!(pid, grace)
    job_id = _read_kit_text_file(d, "kit.job")
    _reap_tagged_workers!(job_id, _read_kit_hosts(d))
    recovered = kit_result_from_dir(d)
    recovered !== nothing && return recovered
    return KitRunResult(
        false,
        kind,
        d,
        log_dir === nothing ? nothing : canonical_local_path(String(log_dir)),
        "terminated",
        1,
    )
end
