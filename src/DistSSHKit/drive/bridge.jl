# Lazy `include` of CLI fragments into `Main` (needs `PROJECT_ROOT`, `ssh_opts()`).

const _KIT_SRC = abspath(joinpath(@__DIR__, "..", ".."))
const _CLI_SRC = joinpath(_KIT_SRC, "cli")

"""Ensure drive runtime (`run_drive_parsed!`) is loaded into `Main`."""
function _ensure_drive_fragments!(project::AbstractString)
    proj = canonical_local_path(project)
    if isdefined(Main, :run_drive_parsed!)
        if isdefined(Main, :PROJECT_ROOT)
            try
                Main.eval(:(PROJECT_ROOT = $proj))
            catch
                # const PROJECT_ROOT from a prior include — leave as-is
            end
        end
        return
    end
    prev_include = get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", nothing)
    ENV["DIST_SSH_KIT_CLI_INCLUDE"] = "1"
    try
        haskey(ENV, "DISTRIBUTED_PROJECT_ROOT") || (ENV["DISTRIBUTED_PROJECT_ROOT"] = proj)
        Core.include(Main, joinpath(_CLI_SRC, "drive.jl"))
        push!(_KIT_CLI_LOADED, "drive.jl")
    finally
        if prev_include === nothing
            delete!(ENV, "DIST_SSH_KIT_CLI_INCLUDE")
        else
            ENV["DIST_SSH_KIT_CLI_INCLUDE"] = prev_include
        end
    end
    return nothing
end

"""Build a `parse_drive_args`-shaped NamedTuple from a session + options."""
function drive_parsed_from_session(
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
    julia::Union{Nothing,AbstractString}=nothing,
    require_all_hosts::Bool=false,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
)
    local_workers = 0
    hosts = Tuple{String,Union{Int,Nothing}}[]
    if workers !== nothing
        local_workers = workers.local_workers
        for (host, n) in workers.remote_workers
            n > 0 && push!(hosts, (host, n))
        end
    else
        for h in session.hosts
            push!(hosts, (h, nothing))
        end
    end
    cli_session = KitCliSession(
        quiet=session.quiet,
        verbosity=session.verbosity,
        yes=session.yes,
        show_version=false,
        hosts_file=session.cli_session.hosts_file,
        hint_surface=hint_surface(session),
    )
    sync_mode = sync isa Symbol ? sync : nothing
    # Default skip=true; --require-git / skip_hash_check=false enables checks.
    # rsync never has remote .git/ parity.
    effective_skip = skip_hash_check || sync_mode === :rsync
    julia_exe = if julia === nothing || strip(String(julia)) == "" ||
            lowercase(strip(String(julia))) == "auto"
        nothing
    else
        String(julia)
    end
    return (
        local_workers=local_workers,
        default_workers=nothing,
        julia=julia_exe,
        skip_hash_check=effective_skip,
        enable_log=enable_log,
        log_dir=log_dir === nothing ? nothing : String(log_dir),
        output_dir=output_dir === nothing ? nothing : String(output_dir),
        explicit_package=package === nothing ? nothing : String(package),
        hosts=hosts,
        script_path=String(script),
        script_args=collect(String, script_args),
        collect_root=nothing,
        collect_hosts=nothing,
        collect_overwrite=nothing,
        sync_mode=sync_mode,
        require_all_hosts=require_all_hosts,
        help=false,
        show_version=false,
        cli_session=cli_session,
        hint_surface=hint_surface(session),
        mem_headroom=Float64(mem_headroom),
        master_gb=Float64(master_gb),
    )
end
