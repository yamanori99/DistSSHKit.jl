# drive! — API entry for driver execution (same core as CLI `drive`).

"""
    drive!(
        session::KitSession,
        script::AbstractString;
        workers=nothing,
        script_args=String[],
        skip_hash_check=true,
        output_dir=nothing,
        enable_log=true,
        log_dir=nothing,
        package=nothing,
        sync=nothing,
    )

Run a driver script on workers described by `session` and optional [`WorkerPlan`](@ref).
Uses the Main-scoped drive runtime (`run_drive_parsed!`). Returns [`DriveResult`](@ref).

Optional `sync=:sync` / `sync=:rsync` runs [`sync!`](@ref) before workers (same as CLI
`--sync` / `--rsync`). Default is no pre-run sync. Git parity is off by default
(`skip_hash_check=true`); pass `skip_hash_check=false` (CLI: `--require-git`) to
require matching remote commits. With `sync=:rsync`, parity stays off even if
`skip_hash_check=false` (no remote `.git/`).

This is the drive step used by [`pipeline!`](@ref) (pipeline syncs separately and does
not pass `sync=` into `drive!`).
"""
function drive!(
    session::KitSession,
    script::AbstractString;
    workers::Union{Nothing,WorkerPlan}=nothing,
    script_args::AbstractVector{<:AbstractString}=String[],
    skip_hash_check::Bool=true,
    output_dir::Union{Nothing,AbstractString}=nothing,
    enable_log::Bool=true,
    log_dir::Union{Nothing,AbstractString}=nothing,
    package::Union{Nothing,AbstractString}=nothing,
    sync::Union{Nothing,Symbol,Bool}=nothing,
)::DriveResult
    apply_session_env!(session)
    _ensure_drive_fragments!(session.project)
    parsed = drive_parsed_from_session(
        session,
        script;
        workers=workers,
        script_args=script_args,
        skip_hash_check=skip_hash_check,
        output_dir=output_dir,
        enable_log=enable_log,
        log_dir=log_dir,
        package=package,
        sync=sync,
    )
    apply_kit_cli_session!(parsed.cli_session)
    original_args = copy(ARGS)
    try
        run_fn = Main.eval(:(run_drive_parsed!))
        code = Base.invokelatest(run_fn, parsed; original_args=original_args)
        return DriveResult(code == 0, Int(code))
    finally
        empty!(ARGS)
        append!(ARGS, original_args)
    end
end
