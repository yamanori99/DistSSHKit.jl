# Cluster inventory: cores / RAM / slot hint + fail-closed health.
# Does not start jobs. Does not drop unreachable hosts from the list.

"""One host in a [`ResourcePool`](@ref). `slots` is 0 when `ok` is false."""
struct HostInventory
    host::String
    ok::Bool
    nproc::Int
    total_gb::Float64
    slots::Int
    message::String
end

"""
Cluster view of listed hosts: totals plus per-host health.

`ok` is false if any listed host failed the probe (fail-closed). `cores`,
`gb`, and `slots` sum **reachable** hosts only; failed rows stay in `hosts`.
Does not change `go` / `drive` `--best-effort`.
"""
struct ResourcePool
    ok::Bool
    hosts::Vector{HostInventory}
    cores::Int
    gb::Float64
    slots::Int
end

function Base.show(io::IO, pool::ResourcePool)
    print(
        io,
        "ResourcePool(ok=",
        pool.ok,
        ", cores=",
        pool.cores,
        ", slots=",
        pool.slots,
        ", hosts=",
        length(pool.hosts),
        ")",
    )
    return nothing
end

const _POOL_PROBE_SCRIPT = string(
    "echo DISTSSHKIT_POOL; ",
    "sysctl -n hw.memsize 2>/dev/null || awk '/MemTotal/{print \$2*1024}' /proc/meminfo 2>/dev/null; ",
    "sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null",
)

function _pool_parse_probe(out::AbstractString)::Union{Nothing, NamedTuple{(:total_gb, :nproc), Tuple{Float64, Int}}}
    lines = String[strip(l) for l in split(String(out), '\n') if !isempty(strip(l))]
    i = findfirst(==("DISTSSHKIT_POOL"), lines)
    i === nothing && return nothing
    length(lines) >= i + 2 || return nothing
    mem = tryparse(Float64, lines[i + 1])
    ncpu = tryparse(Int, lines[i + 2])
    mem === nothing && return nothing
    ncpu === nothing && return nothing
    ncpu <= 0 && return nothing
    return (total_gb = mem / 1024^3, nproc = ncpu)
end

function _pool_slots(
        total_gb::Float64,
        nproc::Int,
        per_worker_gb::Float64;
        mem_headroom::Real,
        parent_gb::Real,
        is_parent::Bool,
    )::Int
    return size_worker_count(
        total_gb,
        nproc,
        per_worker_gb;
        mem_headroom = mem_headroom,
        parent_gb = parent_gb,
        is_parent = is_parent,
    )
end

function _inventory_parent(;
        per_worker_gb::Float64,
        mem_headroom::Real,
        parent_gb::Real,
    )::HostInventory
    res = get_local_resources()
    n = _pool_slots(
        res.total_gb,
        res.nproc,
        per_worker_gb;
        mem_headroom = mem_headroom,
        parent_gb = parent_gb,
        is_parent = true,
    )
    return HostInventory(PARENT_HOST_NAME, true, res.nproc, res.total_gb, n, "ok")
end

function _inventory_child(
        host::AbstractString;
        per_worker_gb::Float64,
        mem_headroom::Real,
        parent_gb::Real,
    )::HostInventory
    h = String(host)
    try
        raw = read(
            pipeline(_host_sync_remote_shell_cmd(h, _POOL_PROBE_SCRIPT); stderr = devnull),
            String,
        )
        parsed = _pool_parse_probe(raw)
        if parsed === nothing
            return HostInventory(h, false, 0, 0.0, 0, "resource probe failed")
        end
        n = _pool_slots(
            parsed.total_gb,
            parsed.nproc,
            per_worker_gb;
            mem_headroom = mem_headroom,
            parent_gb = parent_gb,
            is_parent = false,
        )
        return HostInventory(h, true, parsed.nproc, parsed.total_gb, n, "ok")
    catch e
        _rethrow_missing_host_tool(e)
        return HostInventory(h, false, 0, 0.0, 0, sprint(showerror, e))
    end
end

"""
    pool!(session; gb_per_worker=nothing, mem_headroom, parent_gb) -> ResourcePool

Probe listed hosts for cores and RAM, then a slot hint via the same
RAM/CPU formula as [`size!`](@ref) (no RSS `measure_rss`; that stays on
[`size!`](@ref)). Unreachable hosts stay in the list with `ok=false`.
The pool is `ok` only when every listed host probed successfully.

Does not start workers or rewrite `go` / `drive` membership.
"""
function pool!(
        session::KitSession;
        gb_per_worker::Union{Nothing, Real} = nothing,
        mem_headroom::Real = DEFAULT_MEM_HEADROOM,
        parent_gb::Real = DEFAULT_PARENT_GB,
    )::ResourcePool
    parsed = parse_worker_tokens(session.tokens)
    want_parent = session.include_parent_for_size ||
        parsed.parent_autosize || parsed.parent_workers > 0
    all_hosts = String[]
    want_parent && push!(all_hosts, PARENT_HOST_NAME)
    append!(all_hosts, session.hosts)
    child_hosts = session.hosts
    isempty(all_hosts) && throw(
        ArgumentError(
            explain_no_hosts(; surface = hint_surface(session), kind = :pool),
        )
    )
    return _with_kit_inproc_run!(:pool) do
        apply_session_env!(session)
        pw = Float64(something(gb_per_worker, WORKER_MEMORY_GB_FALLBACK))
        rows = HostInventory[]
        for host in all_hosts
            if is_parent_host_name(host)
                push!(
                    rows, _inventory_parent(;
                        per_worker_gb = pw,
                        mem_headroom = mem_headroom,
                        parent_gb = parent_gb,
                    )
                )
            elseif host in child_hosts
                push!(
                    rows, _inventory_child(
                        host;
                        per_worker_gb = pw,
                        mem_headroom = mem_headroom,
                        parent_gb = parent_gb,
                    )
                )
            end
        end
        healthy = [r for r in rows if r.ok]
        cores = sum(r -> r.nproc, healthy; init = 0)
        gb = sum(r -> r.total_gb, healthy; init = 0.0)
        slots = sum(r -> r.slots, healthy; init = 0)
        return ResourcePool(all(r -> r.ok, rows), rows, cores, gb, slots)
    end
end

"""[`WorkerPlan`](@ref) from pool slot hints (failed hosts contribute 0)."""
function worker_plan_from_pool(pool::ResourcePool)::WorkerPlan
    parent_workers = 0
    child_workers = Dict{String, Int}()
    for row in pool.hosts
        if is_parent_host_name(row.host)
            parent_workers = row.slots
        else
            child_workers[row.host] = row.slots
        end
    end
    return WorkerPlan(parent_workers, child_workers)
end

"""Print cluster totals first, then per-host health."""
function print_pool(pool::ResourcePool; io::IO = stdout)
    failed = count(r -> !r.ok, pool.hosts)
    extra = failed == 0 ? "" : "  ($failed host$(failed == 1 ? "" : "s") unreachable)"
    println(io, "Pool: $(pool.cores) cores  $(round(pool.gb; digits = 1)) GB  $(pool.slots) slots$extra")
    for row in pool.hosts
        shown = is_parent_host_name(row.host) ? PARENT_HOST_NAME : row.host
        if row.ok
            println(
                io,
                "  $(rpad(shown, 16)) ok    $(row.nproc) cores  ",
                "$(round(row.total_gb; digits = 1)) GB  $(row.slots) slots",
            )
        else
            println(io, "  $(rpad(shown, 16)) fail  $(row.message)")
        end
    end
    return nothing
end
