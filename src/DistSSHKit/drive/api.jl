# drive! — API entry for driver execution (same core as CLI `drive`).

"""
    drive!(session::KitSession, script; plan=nothing, args=[], ...)
    drive!(script, workers...; kwargs...)
    drive!(script, workers::AbstractVector; kwargs...)

Run a driver script on workers. Tokens match the CLI (`parenthost:2`, `user@host:1`).

```julia
drive!("job.jl", "parenthost:2"; args=["8"])
drive!(session, "job.jl")  # uses `session.tokens`
```

Prepare remotes with [`setup!`](@ref) or CLI `setup` first. Optional
`sync=:sync` / `sync=:rsync` runs [`sync!`](@ref) (same as `setup!(session, :sync)`
/ `:rsync`) immediately before workers.
Git parity is off by default (`skip_hash_check=true`). With `sync=:rsync`, parity
stays off even if `skip_hash_check=false` (no remote `.git/`).
`require_all_hosts=true` (CLI `--require-all-hosts`) fails if a listed SSH host
did not join, or if collect reported an error (default: best-effort, exit 0).

`mem_headroom` is the RAM fraction for the drive memory preflight (same meaning
as [`size!`](@ref) / CLI `--mem-headroom`). CLI `drive` uses the default
`0.75`. [`pipeline!`](@ref) passes `config.mem_headroom`.

`julia` sets the remote Julia binary (`nothing` / `"auto"` → detect; same as
CLI `--julia`). `plan` is an optional explicit [`WorkerPlan`](@ref).
[`pipeline!`](@ref) syncs separately and does not pass `sync=` into `drive!`.
"""
function drive!(
    session::KitSession,
    script::AbstractString;
    plan::Union{Nothing,WorkerPlan}=nothing,
    args::AbstractVector{<:AbstractString}=String[],
    skip_hash_check::Bool=true,
    output_dir::Union{Nothing,AbstractString}=nothing,
    enable_log::Bool=true,
    log_dir::Union{Nothing,AbstractString}=nothing,
    package::Union{Nothing,AbstractString}=nothing,
    sync::Union{Nothing,Symbol,Bool}=nothing,
    julia::Union{Nothing,AbstractString}=nothing,
    require_all_hosts::Bool=false,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
)::DriveResult
    apply_session_env!(session)
    _ensure_drive_fragments!(session.project)
    resolved = plan
    if resolved === nothing && !isempty(session.tokens)
        resolved = worker_plan_from_tokens(session.tokens; session=session)
    end
    parsed = drive_parsed_from_session(
        session,
        script;
        workers=resolved,
        script_args=args,
        skip_hash_check=skip_hash_check,
        output_dir=output_dir,
        enable_log=enable_log,
        log_dir=log_dir,
        package=package,
        sync=sync,
        julia=julia,
        require_all_hosts=require_all_hosts,
        mem_headroom=mem_headroom,
    )
    apply_kit_cli_session!(parsed.cli_session)
    original_args = copy(ARGS)
    resolved_output_dir = Ref{Union{Nothing,String}}(nothing)
    resolved_log_dir = Ref{Union{Nothing,String}}(nothing)
    resolved_hosts = Ref{Vector{HostRunResult}}(HostRunResult[])
    try
        run_fn = Main.eval(:(run_drive_parsed!))
        code = Base.invokelatest(
            run_fn,
            parsed;
            original_args=original_args,
            resolved_output_dir=resolved_output_dir,
            resolved_log_dir=resolved_log_dir,
            resolved_hosts=resolved_hosts,
        )
        return DriveResult(code == 0, Int(code);
            output_dir=resolved_output_dir[],
            log_dir=resolved_log_dir[],
            failed_step=code == 0 ? nothing : "drive",
            hosts=resolved_hosts[],
        )
    finally
        empty!(ARGS)
        append!(ARGS, original_args)
    end
end

function drive!(
    script::AbstractString,
    workers::AbstractVector{<:AbstractString};
    project::AbstractString=pwd(),
    remote::Union{Nothing,AbstractString}=nothing,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=true,
    kwargs...,
)::DriveResult
    session = KitSession(
        project=project,
        workers=workers,
        remote=remote,
        hosts_file=hosts_file,
        quiet=quiet,
        verbosity=verbosity,
        yes=yes,
    )
    return drive!(session, script; kwargs...)
end

function drive!(script::AbstractString; kwargs...)::DriveResult
    return drive!(script, String[]; kwargs...)
end

function drive!(
    script::AbstractString,
    w1::AbstractString,
    rest::AbstractString...;
    kwargs...,
)::DriveResult
    return drive!(script, String[w1, rest...]; kwargs...)
end
