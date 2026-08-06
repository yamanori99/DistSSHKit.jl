# Result types for the drive / sync API.

"""Default RAM fraction usable for workers in [`size_plan`](@ref) / `size`."""
const DEFAULT_MEM_HEADROOM = 0.75
"""Default GB reserved for the master process on localhost sizing."""
const DEFAULT_MASTER_GB = 0.4
"""Drive preflight: same fraction as [`DEFAULT_MEM_HEADROOM`](@ref)."""
const MEMORY_CAPACITY_FRACTION = DEFAULT_MEM_HEADROOM
"""Multiplier applied to measured RSS when estimating per-worker GB."""
const WORKER_RSS_SAFETY_FACTOR = 1.1
"""Floor for estimated per-worker GB after RSS measurement."""
const WORKER_MEMORY_GB_FLOOR = 0.5
"""Fallback per-worker GB when RSS is unavailable (drive preflight)."""
const WORKER_MEMORY_GB_FALLBACK = 1.5

"""
Convert RSS bytes to a per-worker GB estimate (safety factor + floor).
"""
function rss_bytes_to_worker_gb(rss_bytes::Integer)::Float64
    rss_bytes > 0 || return WORKER_MEMORY_GB_FALLBACK
    gb = rss_bytes / 1024^3 * WORKER_RSS_SAFETY_FACTOR
    return round(max(gb, WORKER_MEMORY_GB_FLOOR), digits=2)
end

"""
    size_worker_count(total_gb, nproc, per_worker_gb; mem_headroom, master_gb, is_localhost)

Pure RAM/CPU cap for one host (shared by CLI and [`compute_worker_plan`](@ref)).
"""
function size_worker_count(
    total_gb::Real,
    nproc::Integer,
    per_worker_gb::Real;
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
    is_localhost::Bool=false,
)::Int
    pw = Float64(per_worker_gb)
    pw <= 0 && return 0
    avail = Float64(total_gb) * Float64(mem_headroom) - (is_localhost ? Float64(master_gb) : 0.0)
    cpu_reserve = is_localhost ? 2 : 1
    return min(
        max(0, floor(Int, avail / pw)),
        max(1, Int(nproc) - cpu_reserve),
    )
end

"""Per-host outcome for sync and similar operations."""
struct HostResult
    host::String
    ok::Bool
    message::String
end

"""Outcome of `sync!` (rsync or git sync). `cancelled` is set when a confirm prompt is aborted."""
struct SyncResult
    ok::Bool
    hosts::Vector{HostResult}
    cancelled::Bool
end

"""Sized worker counts per host (`local_workers` + `remote_workers`)."""
struct WorkerPlan
    local_workers::Int
    remote_workers::Dict{String,Int}
end

WorkerPlan() = WorkerPlan(0, Dict{String,Int}())

"""
Per-host RSS sample from [`measure_rss`](@ref).

`baseline_gb` is after package load. `peak_gb` is after an optional warm-up
probe script (equals baseline when no probe runs). Suggestions use
[`effective_worker_gb`](@ref) = `max(baseline, peak)`.
"""
struct WorkerMemorySample
    baseline_gb::Float64
    peak_gb::Float64
end

"""GB used for worker-count math (`max` of baseline and peak)."""
effective_worker_gb(s::WorkerMemorySample)::Float64 = max(s.baseline_gb, s.peak_gb)

"""Map host → effective GB for [`compute_worker_plan`](@ref)."""
function per_worker_gb_dict(samples::Dict{String,WorkerMemorySample})::Dict{String,Float64}
    return Dict{String,Float64}(h => effective_worker_gb(s) for (h, s) in samples)
end

"""Outcome of [`drive!`](@ref) (and similar CLI steps that return an exit code)."""
struct DriveResult
    ok::Bool
    exit_code::Int
end

"""Outcome of `collect!`."""
struct CollectResult
    ok::Bool
    exit_code::Int
end

"""
    PipelineConfig

Settings for [`pipeline!`](@ref): sync, worker plan, driver run, and optional collect.

Set `sync=false` to skip sync (local-only runs). Set `collect=false` to skip rsync-back
(local outputs are already on disk). Git parity is off by default: when
`skip_hash_check` is `nothing`, checks are skipped. Pass `skip_hash_check=false`
(or CLI `--require-git`) to require matching remote commits.
"""
mutable struct PipelineConfig
    project::String
    hosts::Vector{String}
    remote_root::Union{Nothing,String}
    hosts_file::Union{Nothing,String}
    quiet::Bool
    verbosity::Union{Nothing,Symbol}
    yes::Bool
    include_local_for_size::Bool
    driver::String
    script_args::Vector{String}
    sync::Union{Symbol,Bool,Nothing}
    workers::Union{Nothing,WorkerPlan}
    gb_per_worker::Union{Nothing,Float64}
    size_probe::Union{Nothing,String}
    mem_headroom::Float64
    master_gb::Float64
    skip_hash_check::Union{Nothing,Bool}
    collect_spec::Union{Symbol,Bool,AbstractString,Nothing}
    collect_merge::Bool
    output_dir::Union{Nothing,String}
    enable_log::Bool
    log_dir::Union{Nothing,String}
    package::Union{Nothing,String}
end

function PipelineConfig(;
    project::AbstractString=pwd(),
    hosts::AbstractVector{<:AbstractString}=String[],
    remote_root::Union{Nothing,AbstractString}=nothing,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=false,
    include_local_for_size::Bool=false,
    driver::AbstractString,
    script_args::AbstractVector{<:AbstractString}=String[],
    sync::Union{Symbol,Bool,Nothing}=nothing,
    workers::Union{Nothing,WorkerPlan}=nothing,
    gb_per_worker::Union{Nothing,Real}=nothing,
    size_probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
    skip_hash_check::Union{Nothing,Bool}=nothing,
    collect::Union{Symbol,Bool,AbstractString,Nothing}=nothing,
    collect_merge::Bool=false,
    output_dir::Union{Nothing,AbstractString}=nothing,
    enable_log::Bool=true,
    log_dir::Union{Nothing,AbstractString}=nothing,
    package::Union{Nothing,AbstractString}=nothing,
)
    rr = remote_root === nothing ? nothing : String(strip(String(remote_root)))
    rr !== nothing && isempty(rr) && (rr = nothing)
    hf = hosts_file === nothing ? nothing : String(strip(String(hosts_file)))
    hf !== nothing && isempty(hf) && (hf = nothing)
    gbp = gb_per_worker === nothing ? nothing : Float64(gb_per_worker)
    probe = size_probe === nothing ? nothing : String(size_probe)
    probe !== nothing && isempty(strip(probe)) && (probe = nothing)
    od = output_dir === nothing ? nothing : String(output_dir)
    ld = log_dir === nothing ? nothing : String(log_dir)
    pkg = package === nothing ? nothing : String(package)
    script_args_vec = Base.collect(String, script_args)
    return PipelineConfig(
        canonical_local_path(project),
        [String(h) for h in hosts],
        rr,
        hf,
        quiet,
        verbosity,
        yes,
        include_local_for_size,
        String(driver),
        script_args_vec,
        sync,
        workers,
        gbp,
        probe,
        Float64(mem_headroom),
        Float64(master_gb),
        skip_hash_check,
        collect,
        collect_merge,
        od,
        enable_log,
        ld,
        pkg,
    )
end

"""Combined outcome of [`pipeline!`](@ref). On failure, `failed_step` names the step that stopped."""
struct PipelineResult
    ok::Bool
    sync::Union{Nothing,SyncResult}
    plan::Union{Nothing,WorkerPlan}
    drive::Union{Nothing,DriveResult}
    collect::Union{Nothing,CollectResult}
    driver::String
    failed_step::Union{Nothing,String}
end

PipelineResult(
    ok::Bool,
    sync::Union{Nothing,SyncResult},
    plan::Union{Nothing,WorkerPlan},
    drive::Union{Nothing,DriveResult},
    collect::Union{Nothing,CollectResult},
    driver::String;
    failed_step::Union{Nothing,String}=nothing,
) = PipelineResult(ok, sync, plan, drive, collect, driver, failed_step)

"""Build `drive` host specs from a [`WorkerPlan`](@ref)."""
function drive_host_specs(plan::WorkerPlan)::Vector{String}
    specs = String[]
    if plan.local_workers > 0
        push!(specs, "local:$(plan.local_workers)")
    end
    for (host, n) in plan.remote_workers
        n > 0 && push!(specs, "$(host):$n")
    end
    return specs
end

function SyncResult(
    cancelled::Bool,
    host_results::Vector{HostResult};
    ok::Union{Nothing,Bool}=nothing,
)
    if ok === nothing
        ok = !cancelled && all(hr.ok for hr in host_results)
    end
    return SyncResult(ok, host_results, cancelled)
end
