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
end

function KitProcess(
    process::Base.Process;
    kind::Symbol,
    output_dir::Union{Nothing,AbstractString}=nothing,
    log_dir::Union{Nothing,AbstractString}=nothing,
)
    kind in (:go, :drive) || throw(ArgumentError("KitProcess kind must be :go or :drive, got $(repr(kind))"))
    return KitProcess(process, kind, _optional_path(output_dir), _optional_path(log_dir))
end

"""
    wait(kp::KitProcess) -> KitRunResult

Block until the detached child exits, then return a [`KitRunResult`](@ref).

`failed_step` is `nothing` on success and `"go"` / `"drive"` on a non-zero
exit — the parent cannot recover a more specific in-process step name.
"""
function Base.wait(kp::KitProcess)::KitRunResult
    wait(kp.process)
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
end

"""
    execute!(kind, script, tokens=String[]; output_dir=nothing, args=String[], project=pwd(), sync=nothing, julia=nothing, detached=false, kwargs...) -> KitRunResult or KitProcess

One seam over [`go!`](@ref) / [`drive!`](@ref) for callers that pick the kind
at runtime (`kind ∈ (:go, :drive)`), returning the shared [`KitRunResult`](@ref)
instead of `GoResult` / `DriveResult`.

```julia
execute!(:go, "job.jl", ["masterhost:2"]; args=["8"])
execute!(:drive, "job.jl", ["masterhost:2"]; args=["8"])
wait(execute!(:go, "job.jl", ["masterhost:1"]; detached=true, args=["8"]))
```

`output_dir`, `args`, `project`, `sync`, `julia` are the keywords [`go!`](@ref)
and [`drive!`](@ref) already share. With `detached=false` (default), any other
keyword (`remote`, `hosts_file`, `quiet`, `verbosity`, `yes`, `collect_spec`,
`path_anchor`, `skip_hash_check`, `require_all_hosts`, `plan`, …) is forwarded
verbatim to the chosen function.

`detached=true` spawns `julia -m DistSSHKit go|drive` and returns a
[`KitProcess`](@ref). Keywords are then an allow-list (unknown names throw):
`output_dir`, `args`, `project`, `sync`, `julia`, `quiet`, `verbosity`, `yes`,
`remote`, `hosts_file`, and drive-only `log_dir`, `enable_log`, `package`,
`require_all_hosts`, `skip_hash_check`. `yes` must be `true` (the default):
an unattended child cannot answer a prompt. Child stdio inherits the
parent; pass `stdout` / `stderr` (`IO`) to capture. Parent
`redirect_stdout` does not apply to the subprocess.
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
    stdio_out = get(kwargs, :stdout, nothing)
    stdio_err = get(kwargs, :stderr, nothing)
    proc = if stdio_out === nothing && stdio_err === nothing
        run(child; wait=false)
    else
        run(
            pipeline(
                child;
                stdout=stdio_out === nothing ? Base.stdout : stdio_out,
                stderr=stdio_err === nothing ? Base.stderr : stdio_err,
            );
            wait=false,
        )
    end
    return KitProcess(proc; kind=kind, output_dir=resolved_output, log_dir=resolved_log)
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
