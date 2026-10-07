# Help chrome and the color it uses.

const OUTPUT_WIDTH = 64
const RULE_CHAR = '─'
"""Minimum underline width under a help title (short titles still get a visible rule)."""
const HELP_RULE_MIN_WIDTH = 8
"""Max length for auto-detecting `Heading:` lines in plain `--help` bodies."""
const HELP_SECTION_MAX_LEN = 48

"""Horizontal rule used for section headers (UTF-8 box drawing)."""
rule_line(width::Int = OUTPUT_WIDTH)::String = string(RULE_CHAR)^width

# Colored output (off when NO_COLOR or non-TTY)

"""Whether to use ANSI colors (false when NO_COLOR is set or output is piped)."""
use_colors() = !haskey(ENV, "NO_COLOR") && stdout isa Base.TTY

"""Print `msg` with `color` when the kit would use ANSI (TTY, no `NO_COLOR`)."""
function print_colored(io, msg, color, bold = false)
    return use_colors() ? printstyled(io, msg; color = color, bold = bold) : print(io, msg)
end
const _print_colored = print_colored

"""Help / requirements title text only (no newline). Prefer [`print_help_chrome`](@ref)."""
print_help_title(msg; io = stdout) = _print_colored(io, msg, :cyan, true)

"""
Kit help chrome — every overview / `--help` starts here:

    DistSSHQueue setup
    ──────────────────

Exported for family callers. The signature is stable. Glyphs and colors
are not.
"""
function print_help_chrome(title::AbstractString; io::IO = stdout)
    t = String(title)
    print_help_title(t; io = io)
    println(io)
    w = clamp(length(t), HELP_RULE_MIN_WIDTH, OUTPUT_WIDTH)
    _print_colored(io, rule_line(w) * "\n", :light_black)
    println(io)
    return nothing
end

"""
Section heading (dim) with a trailing blank line so body lines follow immediately.

    Section
    <blank>
      body…
"""
function print_help_section(msg; io = stdout)
    _print_colored(io, String(msg), :light_black, true)
    println(io)
    println(io)
    return nothing
end

"""One or more verbatim help body lines."""
function print_help_lines(io::IO, lines::AbstractString...)
    for line in lines
        println(io, line)
    end
    return nothing
end
print_help_lines(lines::AbstractString...) = print_help_lines(stdout, lines...)

"""One blank line in kit `--help` output."""
print_help_blank(io::IO = stdout) = (println(io); nothing)

"""True when a plain-help line looks like a section heading (`Usage:`, `Options:`)."""
function _help_section_line(line::AbstractString)::Bool
    isempty(line) && return false
    c0 = first(line)
    (c0 == ' ' || c0 == '\t' || c0 == '#') && return false
    last(line) == ':' || return false
    return length(line) <= HELP_SECTION_MAX_LEN
end

"""
Render a plain-text `--help` body under [`print_help_chrome`](@ref).
Non-indented `Heading:` lines are styled like [`print_help_section`](@ref).
"""
function print_help_document(title::AbstractString, body::AbstractString; io::IO = stdout)
    print_help_chrome(title; io = io)
    for line in split(rstrip(String(body), '\n'), '\n'; keepempty = true)
        if _help_section_line(line)
            heading = rstrip(String(line))
            endswith(heading, ':') && (heading = heading[1:prevind(heading, end)])
            _print_colored(io, heading, :light_black, true)
            println(io)
        else
            println(io, line)
        end
    end
    return nothing
end
