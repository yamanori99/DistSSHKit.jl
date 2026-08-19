# pipeline! — sync → size! → drive → collect.

function _parse_env_hosts(raw::AbstractString)::Vector{String}
    s = strip(String(raw))
    isempty(s) && return String[]
    return [strip(h) for h in split(s, ',') if !isempty(strip(h))]
end

function _parse_env_sync_mode(raw::AbstractString)::Union{Symbol,Bool,Nothing}
    s = lowercase(strip(String(raw)))
    isempty(s) && return nothing
    s in ("off", "false", "0", "skip", "no") && return false
    s == "sync" && return :sync
    s == "rsync" && return :rsync
    throw(ArgumentError("invalid SYNC_MODE=$(repr(raw)); use rsync, sync, or off"))
end

function _optional_env_float(name::AbstractString)::Union{Nothing,Float64}
    raw = strip(get(ENV, String(name), ""))
    isempty(raw) && return nothing
    return parse(Float64, raw)
end

function _pipeline_config_driver_path(driver::Union{Nothing,AbstractString})::String
    if driver !== nothing
        d = String(strip(driver::AbstractString))
        !isempty(d) && return d
    end
    env_driver = String(strip(get(ENV, "DRIVER", "")))
    !isempty(env_driver) && return env_driver
    throw(ArgumentError(explain_pipeline_driver_missing(; surface=:api)))
end

"""
    pipeline_config_from_env(; driver=...)

Build [`PipelineConfig`](@ref) from environment variables.

| Variable | Role |
|----------|------|
| `DISTSSHKIT_HOSTS` | Comma-separated worker tokens (`host` / `host:N`) |
| `DISTSSHKIT_HOSTS_FILE` | Hosts file (appended after `DISTSSHKIT_HOSTS`) |
| `DISTRIBUTED_REMOTE_PROJECT_ROOT` | Remote repo root |
| `DISTRIBUTED_PROJECT_ROOT` | Local project root |
| `DRIVER` | Driver script path |
| `GB_PER_WORKER` | Skip RSS probe when set |
| `DISTSSHKIT_SIZE_PROBE` | Optional warm-up script for peak RSS (see size `--probe`) |
| `SYNC_MODE` | `rsync`, `sync`, or `off` |
| `JULIA_DISTRIBUTED_EXE` | Remote Julia path (same as CLI `--julia`; `auto` / unset → detect) |
| `DISTSSHKIT_YES` / `DISTSSHKIT_QUIET` / `DISTSSHKIT_PROGRESS` / `DISTSSHKIT_VERBOSE` | Same as CLI `-y` / `-q` / `--progress` / `--verbose` |
"""
function pipeline_config_from_env(;
    driver::Union{Nothing,AbstractString}=nothing,
)::PipelineConfig
    driver_path = _pipeline_config_driver_path(driver)
    remote_raw = strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))
    hf_raw = strip(get(ENV, "DISTSSHKIT_HOSTS_FILE", ""))
    sync_raw = strip(get(ENV, "SYNC_MODE", ""))
    project_root = strip(get(ENV, "DISTRIBUTED_PROJECT_ROOT", ""))
    want_quiet = _env_flag("DISTSSHKIT_QUIET")
    want_progress = _env_flag("DISTSSHKIT_PROGRESS")
    want_verbose = _env_flag("DISTSSHKIT_VERBOSE")
    n = count(identity, (want_quiet, want_progress, want_verbose))
    n > 1 &&
        throw(ArgumentError("cannot combine DISTSSHKIT_QUIET, DISTSSHKIT_PROGRESS, and DISTSSHKIT_VERBOSE"))
    verbosity = want_quiet ? :quiet : want_progress ? :progress : want_verbose ? :verbose : nothing
    return PipelineConfig(
        project=isempty(project_root) ? pwd() : String(project_root),
        workers=_parse_env_hosts(get(ENV, "DISTSSHKIT_HOSTS", "")),
        remote=isempty(remote_raw) ? nothing : String(remote_raw),
        hosts_file=isempty(hf_raw) ? nothing : String(hf_raw),
        yes=true,
        quiet=want_quiet,
        verbosity=verbosity,
        driver=String(driver_path),
        gb_per_worker=_optional_env_float("GB_PER_WORKER"),
        size_probe=let p = strip(get(ENV, "DISTSSHKIT_SIZE_PROBE", ""))
            isempty(p) ? nothing : String(p)
        end,
        sync=_parse_env_sync_mode(sync_raw),
        julia=let j = strip(get(ENV, "JULIA_DISTRIBUTED_EXE", ""))
            isempty(j) || lowercase(j) == "auto" ? nothing : String(j)
        end,
    )
end

"""Build [`KitSession`](@ref) from a pipeline config."""
function kit_session_from_config(config::PipelineConfig)::KitSession
    return KitSession(
        project=config.project,
        workers=config.tokens,
        remote=config.remote,
        hosts_file=config.hosts_file,
        quiet=config.quiet,
        verbosity=config.verbosity,
        yes=config.yes,
    )
end

"""Resolve sync mode for [`pipeline!`](@ref): `false`, `:rsync`, or `:sync`."""
function resolve_pipeline_sync(
    config::PipelineConfig,
    session::KitSession,
)::Union{Symbol,Bool}
    config.sync === false && return false
    isempty(session.hosts) && return false
    return something(config.sync, false)
end

"""Whether [`pipeline!`](@ref) should rsync results back from remotes."""
function resolve_pipeline_collect(config::PipelineConfig, session::KitSession)::Bool
    if config.collect_spec === false
        return false
    end
    isempty(session.hosts) && return false
    return true
end

"""Local directory to collect into."""
function pipeline_collect_root(config::PipelineConfig)::String
    c = config.collect_spec
    if c isa AbstractString
        return canonical_local_path(c)
    end
    if config.output_dir !== nothing
        return canonical_local_path(something(config.output_dir))
    end
    env = strip(get(ENV, "DISTRIBUTED_OUTPUT_DIR", ""))
    if !isempty(env)
        return canonical_local_path(env)
    end
    driver = abspath(config.driver)
    return joinpath(dirname(driver), "output")
end

"""Resolve whether `drive!` should skip git parity (default: yes / skip)."""
function pipeline_skip_hash_check(config::PipelineConfig)::Bool
    if config.skip_hash_check !== nothing
        return config.skip_hash_check == true
    end
    return true
end

"""
    report_pipeline_errors(result::PipelineResult; io=stderr)

Print a short summary when [`pipeline!`](@ref) failed. Returns `result.ok`.
"""
function report_pipeline_errors(result::PipelineResult; io::IO=stderr)::Bool
    result.ok && return true
    _report_run_header!(io, kit_run_result(result))
    _report_sync_host_errors!(io, result.sync)
    if result.drive !== nothing && !result.drive.ok
        println(io, "  drive exit $(result.drive.exit_code)")
    end
    if result.collect !== nothing && !result.collect.ok
        println(io, "  collect exit $(result.collect.exit_code)")
    end
    return false
end

function report_run_errors(result::PipelineResult; io::IO=stderr)::Bool
    return report_pipeline_errors(result; io=io)
end

"""
    pipeline!(driver, workers...; kwargs...) -> PipelineResult
    pipeline!(driver, workers::AbstractVector; kwargs...) -> PipelineResult
    pipeline!(config::PipelineConfig) -> PipelineResult

Run the usual remote workflow: optional sync, [`size!`](@ref), driver, optional collect.
Does not call [`setup!`](@ref); prepare remotes first.

Worker tokens match the CLI (`local:2`, `user@host:1`). Bare hosts are sized with
[`size!`](@ref). Keyword `args` are passed to the driver; `remote` is the remote
project path. Default `yes=true` skips confirm prompts.

```julia
pipeline!(driver, "local:2"; args=["8"])
pipeline!(driver, "user@h1:1", "user@h2:1"; remote="/path/to/project", args=["8"], collect=true)
```

Remote hosts default to **no** pre-run sync; set `sync=:sync` / `:rsync` explicitly.
Collect defaults on when remotes are present (`collect=false` to skip). Use
`sync=:rsync` only onto a missing/empty remote path (or `setup --delete` /
`setup!(session, :delete)` first).

Returns [`PipelineResult`](@ref); check `result.ok` or use [`report_pipeline_errors`](@ref).
"""
function pipeline!(config::PipelineConfig)::PipelineResult
    session = kit_session_from_config(config)
    driver = abspath(config.driver)
    if !isfile(driver)
        throw(ArgumentError(explain_script_not_found(
            driver,
            session.project;
            surface=hint_surface(session),
            headline="driver not found: $driver",
        )))
    end

    sync_mode = resolve_pipeline_sync(config, session)
    sync_result = nothing
    if sync_mode !== false
        sync_result = sync!(session; mode=sync_mode)
        if !sync_result.ok
            return PipelineResult(
                false,
                sync_result,
                nothing,
                nothing,
                nothing,
                driver;
                failed_step="sync",
                output_dir=config.output_dir,
                log_dir=config.log_dir,
            )
        end
    end

    plan = if isempty(session.tokens)
        WorkerPlan()
    else
        worker_plan_from_tokens(
            session.tokens;
            session=session,
            gb_per_worker=config.gb_per_worker,
            probe=config.size_probe,
            mem_headroom=config.mem_headroom,
            master_gb=config.master_gb,
        )
    end

    do_collect = resolve_pipeline_collect(config, session)
    prev_skip = get(ENV, "DISTRIBUTED_SKIP_COLLECT", nothing)
    if do_collect
        ENV["DISTRIBUTED_SKIP_COLLECT"] = "1"
    end
    drive_result = try
        drive!(
            session,
            driver;
            plan=plan,
            args=config.args,
            skip_hash_check=pipeline_skip_hash_check(config),
            output_dir=config.output_dir,
            enable_log=config.enable_log,
            log_dir=config.log_dir,
            package=config.package,
            julia=config.julia,
        )
    finally
        if do_collect
            if prev_skip === nothing
                delete!(ENV, "DISTRIBUTED_SKIP_COLLECT")
            else
                ENV["DISTRIBUTED_SKIP_COLLECT"] = prev_skip
            end
        end
    end
    if !drive_result.ok
        return PipelineResult(
            false,
            sync_result,
            plan,
            drive_result,
            nothing,
            driver;
            failed_step="drive",
        )
    end

    collect_result = nothing
    if do_collect
        collect_result = collect!(
            session,
            pipeline_collect_root(config);
            merge=config.collect_merge,
        )
        if !collect_result.ok
            return PipelineResult(
                false,
                sync_result,
                plan,
                drive_result,
                collect_result,
                driver;
                failed_step="collect",
            )
        end
    end

    return PipelineResult(
        true,
        sync_result,
        plan,
        drive_result,
        collect_result,
        driver,
    )
end

function pipeline!(
    driver::AbstractString,
    workers::AbstractVector{<:AbstractString};
    kwargs...,
)::PipelineResult
    return pipeline!(PipelineConfig(; driver=driver, workers=workers, kwargs...))
end

function pipeline!(driver::AbstractString; kwargs...)::PipelineResult
    return pipeline!(driver, String[]; kwargs...)
end

function pipeline!(
    driver::AbstractString,
    w1::AbstractString,
    rest::AbstractString...;
    kwargs...,
)::PipelineResult
    return pipeline!(driver, String[w1, rest...]; kwargs...)
end
