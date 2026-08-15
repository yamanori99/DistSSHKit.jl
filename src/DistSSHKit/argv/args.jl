# Small helpers for hand-rolled CLI parsers (drive/setup/size/demo).

"""Cursor over `args` for incremental CLI parsing."""
mutable struct CliCursor
    args::Vector{String}
    i::Int
end

CliCursor(args::AbstractVector{<:AbstractString}) = CliCursor(collect(String, args), 1)

cli_at_end(c::CliCursor)::Bool = c.i > length(c.args)

function cli_current(c::CliCursor)::Union{Nothing,String}
    cli_at_end(c) && return nothing
    return String(c.args[c.i])
end

function cli_consume!(c::CliCursor)
    c.i += 1
    return nothing
end

"""Return the value after the current flag and advance past both."""
function cli_take_value!(c::CliCursor, flag::AbstractString)::String
    c.i >= length(c.args) && throw(ArgumentError("$flag requires a value"))
    val = String(c.args[c.i + 1])
    c.i += 2
    return val
end

function cli_match(c::CliCursor, flags::AbstractVector{<:AbstractString})::Bool
    cur = cli_current(c)
    cur === nothing && return false
    for f in flags
        cur == f && return true
    end
    return false
end
