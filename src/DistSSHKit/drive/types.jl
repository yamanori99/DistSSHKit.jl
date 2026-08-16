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

"""Parsed drive/go worker tokens (counts may still need [`size_plan`](@ref))."""
struct ParsedWorkerTokens
    local_workers::Int
    local_autosize::Bool
    remote_fixed::Dict{String,Int}
    remote_auto::Vector{String}
    remote_hosts::Vector{String}
    tokens::Vector{String}
end

"""
    parse_worker_tokens(tokens) -> ParsedWorkerTokens

Classify CLI-style tokens. Explicit `:N` is fixed; bare hosts are sized later.
`local` / `l` / `localhost` are local; everything else is remote SSH.
"""
function parse_worker_tokens(
    tokens::AbstractVector{<:AbstractString},
)::ParsedWorkerTokens
    local_workers = 0
    local_seen = false
    local_autosize = false
    remote_fixed = Dict{String,Int}()
    remote_auto = String[]
    remote_hosts = String[]
    seen_remote = Set{String}()
    out_tokens = String[String(t) for t in tokens]

    for raw in out_tokens
        host, n = split_host_workers_spec(raw)
        if is_local_host_name(host)
            local_seen && throw(ArgumentError(
                "duplicate local worker token; use one of l:N, local:N, or localhost:N",
            ))
            local_seen = true
            if n === nothing
                local_autosize = true
            else
                local_workers = Int(n)
            end
        else
            if !(host in seen_remote)
                push!(remote_hosts, host)
                push!(seen_remote, host)
            end
            if n === nothing
                push!(remote_auto, host)
            else
                remote_fixed[host] = Int(n)
            end
        end
    end
    return ParsedWorkerTokens(
        local_workers,
        local_autosize,
        remote_fixed,
        remote_auto,
        remote_hosts,
        out_tokens,
    )
end

"""True when every token has an explicit worker/slot count (`:N`)."""
function worker_tokens_fully_specified(parsed::ParsedWorkerTokens)::Bool
    return !parsed.local_autosize && isempty(parsed.remote_auto)
end

"""SSH host names from tokens (local tokens omitted)."""
function remote_hosts_from_tokens(tokens::AbstractVector{<:AbstractString})::Vector{String}
    return parse_worker_tokens(tokens).remote_hosts
end

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

Settings for [`pipeline!`](@ref): sync, worker tokens, driver run, and optional collect.

Worker placement uses CLI-style tokens (`local:2`, `user@host:1`). Bare hosts are
sized via [`size!`](@ref). Set `sync=false` to skip sync. Set `collect=false`
to skip rsync-back. Git parity is off by default; pass `skip_hash_check=false`
(or CLI `--require-git`) to require matching remote commits.

`julia` sets the remote Julia binary (`nothing` / `"auto"` → detect; same as
CLI `--julia`). Prefer [`pipeline!(driver, workers...; …)`](@ref pipeline!) for
day-to-day use.
"""
mutable struct PipelineConfig
    project::String
    tokens::Vector{String}
    remote::Union{Nothing,String}
    hosts_file::Union{Nothing,String}
    quiet::Bool
    verbosity::Union{Nothing,Symbol}
    yes::Bool
    driver::String
    args::Vector{String}
    sync::Union{Symbol,Bool,Nothing}
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
    julia::Union{Nothing,String}
end

function PipelineConfig(;
    project::AbstractString=pwd(),
    workers::AbstractVector{<:AbstractString}=String[],
    remote::Union{Nothing,AbstractString}=nothing,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=true,
    driver::AbstractString,
    args::AbstractVector{<:AbstractString}=String[],
    sync::Union{Symbol,Bool,Nothing}=nothing,
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
    julia::Union{Nothing,AbstractString}=nothing,
)
    rr = remote === nothing ? nothing : String(strip(String(remote)))
    rr !== nothing && isempty(rr) && (rr = nothing)
    hf = hosts_file === nothing ? nothing : String(strip(String(hosts_file)))
    hf !== nothing && isempty(hf) && (hf = nothing)
    gbp = gb_per_worker === nothing ? nothing : Float64(gb_per_worker)
    probe = size_probe === nothing ? nothing : String(size_probe)
    probe !== nothing && isempty(strip(probe)) && (probe = nothing)
    od = output_dir === nothing ? nothing : String(output_dir)
    ld = log_dir === nothing ? nothing : String(log_dir)
    pkg = package === nothing ? nothing : String(package)
    jl = if julia === nothing || isempty(strip(String(julia))) ||
            lowercase(strip(String(julia))) == "auto"
        nothing
    else
        String(julia)
    end
    return PipelineConfig(
        canonical_local_path(project),
        String[String(t) for t in workers],
        rr,
        hf,
        quiet,
        verbosity,
        yes,
        String(driver),
        Base.collect(String, args),
        sync,
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
        jl,
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
