# Which package the user typed after `julia -m`. The outermost `main` sets it.

const _CLI_ENTRY = Ref{Union{Nothing, Symbol}}(nothing)

"""Package after `julia -m`. `DistSSHKit` until an outermost `main` sets one."""
function cli_entry()::Symbol
    return something(_CLI_ENTRY[], :DistSSHKit)
end

"""`julia -m DistSSHKit` or the package that owns this CLI entry."""
cli_m()::String = "julia -m $(cli_entry())"

"""`julia --project=. -m <entry>`."""
cli_m_project()::String = "julia --project=. -m $(cli_entry())"

"""
Leading `qhost ` for Kit's queue-host commands.

Empty when the entry is DistSSHQueue (`julia -m DistSSHQueue setup`).
"""
function cli_qhost()::String
    return cli_entry() === :DistSSHKit ? "qhost " : ""
end

"""Help title: `DistSSHQueue setup`."""
cli_heading(rest::AbstractString)::String = "$(cli_entry()) $(rest)"

"""Help title for a queue-host command. Kit keeps the `qhost` word."""
function cli_qhost_heading(rest::AbstractString)::String
    return "$(cli_entry()) $(cli_qhost())$(rest)"
end

"""
Set the CLI entry for `f` when none is set.

An inner `main` does not replace the outer one, and does not clear it.
"""
function with_cli_entry(f, pkg::Symbol)
    _CLI_ENTRY[] !== nothing && return f()
    _CLI_ENTRY[] = pkg
    try
        return f()
    finally
        _CLI_ENTRY[] = nothing
    end
end
