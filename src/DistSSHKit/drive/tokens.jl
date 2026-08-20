# Resolve CLI-style worker tokens to a concrete [`WorkerPlan`](@ref).

"""
Build a [`WorkerPlan`](@ref) from tokens.

When any host lacks `:N`, run [`size!`](@ref) on `session` (must list those
hosts; set `include_local_for_size` for bare `local`). Explicit `:N` wins over size.
"""
function worker_plan_from_tokens(
    tokens::AbstractVector{<:AbstractString};
    session::Union{Nothing,KitSession}=nothing,
    gb_per_worker::Union{Nothing,Real}=nothing,
    probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
)::WorkerPlan
    parsed = parse_worker_tokens(tokens)
    local_n = parsed.local_workers
    remotes = Dict{String,Int}(parsed.remote_workers)

    if worker_tokens_fully_specified(parsed)
        return WorkerPlan(local_n, remotes)
    end

    session === nothing && throw(ArgumentError(
        "worker tokens need size! for hosts without :N; pass a KitSession",
    ))
    sized = size!(
        session;
        gb_per_worker=gb_per_worker,
        probe=probe,
        mem_headroom=mem_headroom,
        master_gb=master_gb,
    )
    if parsed.local_autosize
        local_n = sized.local_workers
    end
    for h in parsed.remote_auto
        remotes[h] = get(sized.remote_workers, h, 0)
    end
    return WorkerPlan(local_n, remotes)
end
