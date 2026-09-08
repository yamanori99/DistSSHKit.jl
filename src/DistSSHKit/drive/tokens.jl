# Resolve CLI-style worker tokens to a concrete [`WorkerPlan`](@ref).

"""
Build a [`WorkerPlan`](@ref) from tokens.

Every token must have `:N`. Omitted counts are not sized here (`size!` / CLI
`size` are separate; paste the printed tokens).
"""
function worker_plan_from_tokens(
        tokens::AbstractVector{<:AbstractString},
    )::WorkerPlan
    parsed = parse_worker_tokens(tokens)
    local_n = parsed.parent_workers
    remotes = Dict{String, Int}(parsed.child_workers)

    worker_tokens_fully_specified(parsed) || throw(
        ArgumentError(explain_bare_placement_tokens(tokens; surface = :api)),
    )
    return WorkerPlan(local_n, remotes)
end
