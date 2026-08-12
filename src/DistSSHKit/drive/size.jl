# size_plan — worker count sizing (structured return).

"""
    compute_worker_plan(
        all_hosts, remote_hosts, per_worker_gb;
        mem_headroom=DEFAULT_MEM_HEADROOM, master_gb=DEFAULT_MASTER_GB,
    )

Pure worker-count math (same rules as `size` CLI). Returns [`WorkerPlan`](@ref).
"""
function compute_worker_plan(
    all_hosts::Vector{String},
    remote_hosts::Vector{String},
    per_worker_gb::Dict{String,Float64};
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
)::WorkerPlan
    local_workers = 0
    remote_workers = Dict{String,Int}()
    local_total, local_nproc = get_local_resources()

    for host in all_hosts
        if host == "localhost"
            res = (total_gb=local_total, nproc=local_nproc)
        else
            res = (
                total_gb=something(get_remote_total_gb(host), 0.0),
                nproc=something(get_remote_nproc(host), 1),
            )
        end
        pw = get(per_worker_gb, host, WORKER_MEMORY_GB_FALLBACK)
        n = size_worker_count(
            res.total_gb,
            res.nproc,
            pw;
            mem_headroom=mem_headroom,
            master_gb=master_gb,
            is_localhost=(host == "localhost"),
        )
        if host == "localhost"
            local_workers = n
        elseif host in remote_hosts
            remote_workers[host] = n
        end
    end
    return WorkerPlan(local_workers, remote_workers)
end

"""
    size_plan(
        session::KitSession;
        gb_per_worker=nothing, probe=nothing,
        mem_headroom=DEFAULT_MEM_HEADROOM, master_gb=DEFAULT_MASTER_GB,
    )

Estimate worker counts for hosts in `session`. When `gb_per_worker` is omitted,
probes each host via [`measure_rss`](@ref) (package-load baseline, optional
warm-up `probe` script for peak RSS). Counts use [`effective_worker_gb`](@ref).

Returns [`WorkerPlan`](@ref). Prefer [`size!`](@ref) for the bang-style name.
"""
function size_plan(
    session::KitSession;
    gb_per_worker::Union{Nothing,Real}=nothing,
    probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
)::WorkerPlan
    apply_session_env!(session)
    all_hosts, remote_hosts = session_size_hosts(session)
    isempty(all_hosts) && throw(ArgumentError("KitSession has no hosts for size_plan"))

    per_worker_gb = Dict{String,Float64}()
    if gb_per_worker !== nothing
        g = Float64(gb_per_worker)
        for h in all_hosts
            per_worker_gb[h] = g
        end
    else
        measured = measure_rss(
            session.project,
            remote_hosts;
            include_local=session.include_local_for_size,
            probe=probe,
        )
        isempty(measured) && throw(
            ErrorException("per-worker memory measurement failed; pass gb_per_worker=..."),
        )
        for h in all_hosts
            if haskey(measured, h)
                per_worker_gb[h] = effective_worker_gb(measured[h])
            else
                per_worker_gb[h] = WORKER_MEMORY_GB_FALLBACK
            end
        end
    end

    return compute_worker_plan(
        all_hosts,
        remote_hosts,
        per_worker_gb;
        mem_headroom=mem_headroom,
        master_gb=master_gb,
    )
end

"""
    size!(session::KitSession; kwargs...)

Alias for [`size_plan`](@ref). Prefer this name to match `sync!` / `drive!` /
`collect!`. Same arguments and [`WorkerPlan`](@ref) return.
"""
function size!(session::KitSession; kwargs...)
    return size_plan(session; kwargs...)
end
