# Resolve CLI-style worker tokens to a concrete [`WorkerPlan`](@ref).

"""
Build a [`WorkerPlan`](@ref) from tokens.

When any host lacks `:N`, run [`size!`](@ref) on `session` (must list those
hosts; set `include_parent_for_size` for bare `parent`). Explicit `:N` wins over size.
"""
function worker_plan_from_tokens(
    tokens::AbstractVector{<:AbstractString};
    session::Union{Nothing,KitSession}=nothing,
    gb_per_worker::Union{Nothing,Real}=nothing,
    probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    parent_gb::Real=DEFAULT_PARENT_GB,
)::WorkerPlan
    parsed = parse_worker_tokens(tokens)
    local_n = parsed.parent_workers
    remotes = Dict{String,Int}(parsed.child_workers)

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
        parent_gb=parent_gb,
    )
    if parsed.parent_autosize
        local_n = sized.parent_workers
    end
    for h in parsed.child_auto
        remotes[h] = get(sized.child_workers, h, 0)
    end
    return WorkerPlan(local_n, remotes)
end
