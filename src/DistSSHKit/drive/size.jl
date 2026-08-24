# size! — worker count sizing (structured return).

"""
    compute_worker_plan(
        all_hosts, child_hosts, per_worker_gb;
        mem_headroom=DEFAULT_MEM_HEADROOM, parent_gb=DEFAULT_PARENT_GB,
    )

Pure worker-count math (same rules as `size` CLI). Returns [`WorkerPlan`](@ref).
"""
function compute_worker_plan(
    all_hosts::Vector{String},
    child_hosts::Vector{String},
    per_worker_gb::Dict{String,Float64};
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    parent_gb::Real=DEFAULT_PARENT_GB,
)::WorkerPlan
    parent_workers = 0
    child_workers = Dict{String,Int}()
    local_total, local_nproc = get_local_resources()

    for host in all_hosts
        if is_parent_host_name(host)
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
            parent_gb=parent_gb,
            is_parent=is_parent_host_name(host),
        )
        if is_parent_host_name(host)
            parent_workers = n
        elseif host in child_hosts
            child_workers[host] = n
        end
    end
    return WorkerPlan(parent_workers, child_workers)
end

"""
    size!(
        session::KitSession;
        gb_per_worker=nothing, probe=nothing,
        mem_headroom=DEFAULT_MEM_HEADROOM, parent_gb=DEFAULT_PARENT_GB,
    )

Estimate worker counts for hosts in `session`. When `gb_per_worker` is omitted,
probes each host via `measure_rss` (package-load baseline, optional
warm-up `probe` script for peak RSS). Counts use `effective_worker_gb`.

Returns [`WorkerPlan`](@ref).
"""
function size!(
    session::KitSession;
    gb_per_worker::Union{Nothing,Real}=nothing,
    probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    parent_gb::Real=DEFAULT_PARENT_GB,
)::WorkerPlan
    apply_session_env!(session)
    all_hosts, child_hosts = session_size_hosts(session)
    isempty(all_hosts) && throw(ArgumentError(
        explain_no_hosts(; surface=hint_surface(session), kind=:size),
    ))

    per_worker_gb = Dict{String,Float64}()
    if gb_per_worker !== nothing
        g = Float64(gb_per_worker)
        for h in all_hosts
            per_worker_gb[h] = g
        end
    else
        measured = measure_rss(
            session.project,
            child_hosts;
            include_parent=session.include_parent_for_size,
            probe=probe,
            hint_surface=hint_surface(session),
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
        child_hosts,
        per_worker_gb;
        mem_headroom=mem_headroom,
        parent_gb=parent_gb,
    )
end
