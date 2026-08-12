# Path helpers

"""Absolute local path with `~` expanded (canonical form for file I/O and comparisons)."""
canonical_local_path(path::AbstractString)::String = String(abspath(expanduser(String(path))))

"""Shorten absolute paths by replacing the home directory prefix with `~`."""
short_path(path::String) = let home = expanduser("~")
    startswith(path, home) ? "~" * path[length(home)+1:end] : path
end

"""
Paths under `anchor` → `relpath` from `anchor` (POSIX-style separators in the result).
Otherwise fall back to `short_path` (home as `~`).
"""
function display_path(path::AbstractString, anchor::AbstractString)::String
    ap = try
        canonical_local_path(path)
    catch
        return short_path(String(path))
    end
    an = try
        canonical_local_path(anchor)
    catch
        return short_path(String(path))
    end
    ap == an && return "."
    sep = Sys.iswindows() ? '\\' : '/'
    prefix = endswith(an, string(sep)) ? String(an) : an * sep
    if startswith(ap, prefix)
        return String(relpath(ap, an))
    end
    return short_path(String(path))
end

"""Read `name = "..."` from `proj_dir/Project.toml`; return `nothing` if missing or unreadable."""
function project_package_name(proj_dir::AbstractString)::Union{Nothing,String}
    path = joinpath(proj_dir, "Project.toml")
    isfile(path) || return nothing
    try
        m = match(r"name\s*=\s*\"([^\"]+)\"", read(path, String))
        m === nothing && return nothing
        cap = m.captures[1]
        return cap isa AbstractString ? String(cap) : nothing
    catch
        return nothing
    end
end

"""
Walk upward from `start_dir` to find the directory that should be passed to
`Pkg.activate` on workers.

If the first `Project.toml` found is the **vendored stub** (its `name` is
`DistSSHKit`, matching this kit’s own `Project.toml`) and the parent
directory also has a `Project.toml`, skip it and keep walking so scripts
co-located with the kit inherit the application project root (regardless of
the kit folder’s basename).
"""
function resolve_pkg_project_dir(start_dir::AbstractString)::String
    test_dir = abspath(String(start_dir))
    fallback = dirname(test_dir)
    for _ in 1:24
        pt = joinpath(test_dir, "Project.toml")
        if isfile(pt)
            parent = dirname(test_dir)
            stub = project_package_name(test_dir)
            skip_stub = stub == "DistSSHKit" && isfile(joinpath(parent, "Project.toml"))
            skip_stub || return test_dir
        end
        parent = dirname(test_dir)
        parent == test_dir && return fallback
        test_dir = parent
    end
    return fallback
end

"""
Short label for a project root in console output.
"""
function cli_project_disp(
    project_root::AbstractString,
    path_anchor::AbstractString=canonical_local_path(project_root),
)::String
    s = display_path(String(project_root), path_anchor)
    return s == "." ? basename(abspath(String(project_root))) : s
end

"""
Default local project root for `drive.jl` / `setup.jl` / `size.jl`.

- Standalone kit checkout (`Project.toml` at repo root): the kit directory.
- Embedded under a host app (`…/DistSSHKit/` stub next to the app `Project.toml`): the app root.
"""
function kit_project_root(kit_dir::AbstractString)::String
    root = canonical_local_path(kit_dir)
    # `src/cli/*.jl` pass `@__DIR__` (= …/src/cli); strip down to the kit root.
    if basename(root) == "cli"
        root = dirname(root)
    end
    if basename(root) == "src"
        root = dirname(root)
    end
    isfile(joinpath(root, "Project.toml")) || return dirname(root)
    parent = dirname(root)
    stub = project_package_name(root)
    if stub == "DistSSHKit" && isfile(joinpath(parent, "Project.toml"))
        return parent
    end
    return root
end

# Output formatting

const OUTPUT_WIDTH = 64
const RULE_CHAR = '─'
"""Minimum underline width under a help title (short titles still get a visible rule)."""
const HELP_RULE_MIN_WIDTH = 8
"""Max length for auto-detecting `Heading:` lines in plain `--help` bodies."""
const HELP_SECTION_MAX_LEN = 48

"""Horizontal rule used for section headers (UTF-8 box drawing)."""
rule_line(width::Int=OUTPUT_WIDTH)::String = string(RULE_CHAR)^width

# Log file

const LOG_FILE_HANDLE = Ref{Union{IO,Nothing}}(nothing)
const KIT_OUTPUT_QUIET = Ref(false)
const KIT_NONINTERACTIVE = Ref(false)
"""`:verbose` | `:progress` | `:quiet` — see [`kit_verbosity`](@ref)."""
const KIT_VERBOSITY = Ref{Symbol}(:verbose)

kit_verbosity()::Symbol = KIT_VERBOSITY[]
kit_output_quiet()::Bool = KIT_VERBOSITY[] === :quiet
"""True when detailed kit lines should print (`:verbose` only)."""
kit_output_detail()::Bool = KIT_VERBOSITY[] === :verbose
"""True when the thin phase bar is active (`:progress`)."""
kit_output_progress()::Bool = KIT_VERBOSITY[] === :progress
kit_noninteractive()::Bool = KIT_NONINTERACTIVE[]

function set_kit_verbosity!(v::Symbol)
    v in (:verbose, :progress, :quiet) ||
        throw(ArgumentError("kit verbosity must be :verbose, :progress, or :quiet (got $v)"))
    KIT_VERBOSITY[] = v
    KIT_OUTPUT_QUIET[] = v === :quiet
    return nothing
end

"""Compat: `true` → `:quiet`, `false` → `:verbose` (clears `:progress`)."""
function set_kit_output_quiet!(v::Bool)
    set_kit_verbosity!(v ? :quiet : :verbose)
    return nothing
end
set_kit_noninteractive!(v::Bool) = (KIT_NONINTERACTIVE[] = v; nothing)

"""Append to the open kit log file (no-op when none). Independent of verbosity."""
function _kit_log_write(msg::AbstractString)
    h = LOG_FILE_HANDLE[]
    h === nothing && return
    print(h, msg)
    flush(h)
    return nothing
end

function _kit_log_writeln(msg::AbstractString="")
    h = LOG_FILE_HANDLE[]
    h === nothing && return
    println(h, msg)
    flush(h)
    return nothing
end

"""Kit text → terminal when `:verbose`, always to kit log when open."""
function write_both(msg::String; color::Symbol=:normal, bold::Bool=false)
    if kit_output_detail()
        if color == :normal && !bold
            print(msg)
        else
            printstyled(msg; color=color, bold=bold)
        end
    end
    _kit_log_write(msg)
    return nothing
end

function writeln_both(msg::String=""; color::Symbol=:normal, bold::Bool=false)
    if kit_output_detail()
        if color == :normal && !bold
            println(msg)
        else
            printstyled(msg * "\n"; color=color, bold=bold)
        end
    end
    _kit_log_writeln(msg)
    return nothing
end

function init_log_file(output_dir::String; prefix::String="drive", path_anchor::Union{Nothing,String}=nothing)
    isdir(output_dir) || mkpath(output_dir)
    timestamp = Dates.format(now(), dateformat"yyyy-mm-ddTHHMMSS")
    log_file = joinpath(output_dir, "$(prefix)_$(timestamp).log")
    LOG_FILE_HANDLE[] = open(log_file, "w")
    log_disp = path_anchor === nothing ? short_path(log_file) : display_path(log_file, path_anchor)
    writeln_field("Log file", log_disp)
    return log_file
end

function close_log_file()
    if LOG_FILE_HANDLE[] !== nothing
        flush(LOG_FILE_HANDLE[])
        close(LOG_FILE_HANDLE[])
        LOG_FILE_HANDLE[] = nothing
    end
end

"""IO that writes to both primary (e.g. stdout) and secondary (e.g. log file).
For secondary: line-buffered — only complete lines are written. Progress bar
updates (\\r overwrites) are not written to log, avoiding bloat."""
mutable struct TeeIO{P<:IO,S<:Union{IO,Nothing}} <: IO
    primary::P
    secondary::S
    linebuf::Vector{UInt8}
end

function TeeIO(primary::IO, secondary::Union{IO,Nothing})
    TeeIO{typeof(primary),typeof(secondary)}(primary, secondary, UInt8[])
end

function Base.write(io::TeeIO, b::UInt8)
    write(io.primary, b)
    sec = io.secondary
    if sec isa IO
        if b == 0x0d          # \r — discard (progress-bar overwrite)
            empty!(io.linebuf)
        elseif b == 0x0a      # \n — flush complete line to log
            write(sec, io.linebuf)
            write(sec, b)
            flush(sec)
            empty!(io.linebuf)
        else
            push!(io.linebuf, b)
        end
    end
    return 1
end

function _teeio_write_vector!(io::TeeIO, b::AbstractVector{UInt8})::Int
    write(io.primary, b)
    sec = io.secondary
    if sec isa IO
        for x in b
            if x == 0x0d
                empty!(io.linebuf)
            elseif x == 0x0a
                write(sec, io.linebuf)
                write(sec, x)
                flush(sec)
                empty!(io.linebuf)
            else
                push!(io.linebuf, x)
            end
        end
    end
    return length(b)
end

function Base.write(io::TeeIO, b::AbstractVector{UInt8})
    return _teeio_write_vector!(io, b)
end

# `AbstractVector{UInt8}` alone is ambiguous with Base's `write(::IO, ::StridedArray)`
# for `Vector{UInt8}` / other strided inputs; this narrower method disambiguates.
function Base.write(io::TeeIO, b::StridedVector{UInt8})
    return _teeio_write_vector!(io, b)
end

# Also ambiguous with Base's `write(::IO, ::Base.CodeUnits)` (e.g. `write(io, codeunits(str))`);
# this narrower method disambiguates. `where S` (rather than the bare UnionAll
# `Base.CodeUnits{UInt8}`) keeps `b`'s type concrete for the compiler/linter.
function Base.write(io::TeeIO, b::Base.CodeUnits{UInt8,S}) where {S<:AbstractString}
    return _teeio_write_vector!(io, Vector{UInt8}(b))
end

function Base.flush(io::TeeIO)
    flush(io.primary)
    sec = io.secondary
    if sec isa IO && !isempty(io.linebuf)
        write(sec, io.linebuf)
        flush(sec)
    end
    nothing
end

"""Shell-quoted record of this subcommand's ARGS (no `julia -m` prefix)."""
subcommand_args_record(subcommand::AbstractString, args::Vector{String})::String =
    Base.shell_escape(String(subcommand), args...)

"""Julia binary / project / threads for the kit log (best-effort)."""
function julia_env_record()::Vector{Pair{String,String}}
    opts = Base.JLOptions()
    out = Pair{String,String}[]
    bin = opts.julia_bin == C_NULL ? nothing : unsafe_string(opts.julia_bin)
    bin === nothing || push!(out, "Julia binary" => bin)
    proj = opts.project == C_NULL ? "" : unsafe_string(opts.project)
    isempty(proj) || push!(out, "Project" => proj)
    opts.nthreads == 0 ||
        push!(out, "Threads" => "$(Threads.nthreads()) (default pool; interactive pool not recorded)")
    return out
end

print_separator(; width::Int=OUTPUT_WIDTH) =
    writeln_both(rule_line(width); color=:light_black)

"""Title + dim rule (kit banner)."""
function print_header(title::String; width::Int=OUTPUT_WIDTH)
    writeln_both(title; color=:cyan, bold=true)
    print_separator(; width=width)
    return nothing
end

"""`Label: value` line (dim label when colors are on)."""
function writeln_field(label::AbstractString, value)
    prefix = "$(label): "
    text = sprint(print, value)
    if kit_output_detail()
        if use_colors()
            printstyled(prefix; color=:light_black)
            println(text)
        else
            println(prefix, text)
        end
    end
    _kit_log_writeln(prefix * text)
    return nothing
end

# Colored output (off when NO_COLOR or non-TTY)

"""Whether to use ANSI colors (false when NO_COLOR is set or output is piped)."""
use_colors() = !haskey(ENV, "NO_COLOR") && stdout isa Base.TTY

function _print_colored(io, msg, color, bold=false)
    use_colors() ? printstyled(io, msg; color=color, bold=bold) : print(io, msg)
end

function print_ok(msg; io=stdout, bold=false)
    if kit_output_detail()
        _print_colored(io, msg, :green, bold)
    end
    _kit_log_write(string(msg))
    return nothing
end

# Wait spinner (`:verbose` TTY only)

const SPINNER_FRAMES = ('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')

_spinner_can_draw()::Bool =
    kit_output_detail() && stdout isa Base.TTY && !haskey(ENV, "NO_COLOR")

"""
    kit_spin!(prefix, f) -> result of f()

While `f` runs, animate a light spinner after `prefix` on the current TTY line
(`:light_black`). On exit, clear the spinner and leave `prefix` so the caller
can print `✓` / `✗`. Outside `:verbose` TTY (quiet / progress / pipe), just
runs `f` with no animation.

Call with a do-block: `kit_spin!("label: ") do ... end`.
"""
function kit_spin!(f, prefix::AbstractString)
    if !_spinner_can_draw()
        return f()
    end
    done = Ref(false)
    prefix_s = String(prefix)
    spinner_task = @async begin
        i = 1
        while !done[]
            print(stdout, '\r', prefix_s)
            if use_colors()
                printstyled(stdout, SPINNER_FRAMES[i]; color=:light_black)
            else
                print(stdout, SPINNER_FRAMES[i])
            end
            print(stdout, "\e[K")
            flush(stdout)
            i = i == length(SPINNER_FRAMES) ? 1 : i + 1
            sleep(0.08)
        end
    end
    try
        return f()
    finally
        done[] = true
        wait(spinner_task)
        print(stdout, '\r', prefix_s, "\e[K")
        flush(stdout)
    end
end

"""Always-visible error text (terminal + kit log)."""
function print_err(msg; io=stdout, bold=false)
    _print_colored(io, msg, :red, bold)
    _kit_log_write(string(msg))
    return nothing
end

function print_info(msg; io=stdout, bold=false)
    if kit_output_detail()
        _print_colored(io, msg, :cyan, bold)
    end
    _kit_log_write(string(msg))
    return nothing
end

"""Always-visible warning text (terminal + kit log)."""
function print_warn(msg; io=stdout, bold=false)
    _print_colored(io, msg, :yellow, bold)
    _kit_log_write(string(msg))
    return nothing
end

"""Always-visible fatal line (terminal + kit log)."""
function println_fatal(msg::AbstractString=""; io::IO=stdout)
    println(io, msg)
    _kit_log_writeln(msg)
    return nothing
end

"""Error mark; same terminal gate as `writeln_both`."""
function print_progress_err(msg; kwargs...)
    if !kit_output_detail()
        _kit_log_write(string(msg))
        return nothing
    end
    return print_err(msg; kwargs...)
end

"""Warning mark; same terminal gate as `writeln_both`."""
function print_progress_warn(msg; kwargs...)
    if !kit_output_detail()
        _kit_log_write(string(msg))
        return nothing
    end
    return print_warn(msg; kwargs...)
end

"""Help / requirements title text only (no newline). Prefer [`print_help_chrome`](@ref)."""
print_help_title(msg; io=stdout) = _print_colored(io, msg, :cyan, true)

# Thin phase progress (`--progress`)

const PROGRESS_BAR_WIDTH = 16
const PROGRESS_FILL_CHAR = '━'
const PROGRESS_EMPTY_CHAR = '─'

mutable struct KitProgressState
    title::String
    steps::Int
    done::Int
    label::String
end

const KIT_PROGRESS = Ref{Union{Nothing,KitProgressState}}(nothing)

function _progress_bar_string(done::Int, total::Int; width::Int=PROGRESS_BAR_WIDTH)::String
    t = max(total, 1)
    d = clamp(done, 0, t)
    filled = round(Int, width * d / t)
    return string(PROGRESS_FILL_CHAR)^filled * string(PROGRESS_EMPTY_CHAR)^(width - filled)
end

function _progress_line(state::KitProgressState)::String
    bar = _progress_bar_string(state.done, state.steps)
    return "  $bar  $(state.label) · $(state.done)/$(state.steps)"
end

_progress_can_draw()::Bool =
    kit_output_progress() && stdout isa Base.TTY && !haskey(ENV, "NO_COLOR")

function _progress_draw!(state::KitProgressState; newline::Bool=false, color::Symbol=:normal)
    !_progress_can_draw() && return nothing
    bar = _progress_bar_string(state.done, state.steps)
    suffix = "  $(state.label) · $(state.done)/$(state.steps)"
    print(stdout, '\r', "  ")
    if color === :normal
        print(stdout, bar)
        if use_colors()
            printstyled(stdout, suffix; color=:light_black)
        else
            print(stdout, suffix)
        end
    else
        line = bar * suffix
        if use_colors()
            printstyled(stdout, line; color=color)
        else
            print(stdout, line)
        end
    end
    print(stdout, "\e[K")
    newline && println(stdout)
    flush(stdout)
    return nothing
end

function _progress_log!(state::KitProgressState)
    _kit_log_writeln("progress: $(state.label) ($(state.done)/$(state.steps))")
    return nothing
end

"""
Start a thin phase bar for `--progress` mode.

`steps` is the total number of phases. Outside `:progress`, updates state only
(no terminal bar / progress log lines).
"""
function kit_progress_begin!(title::AbstractString; steps::Int)
    steps < 1 && throw(ArgumentError("kit_progress_begin!: steps must be ≥ 1"))
    state = KitProgressState(String(title), steps, 0, String(title))
    KIT_PROGRESS[] = state
    if kit_output_progress()
        _progress_log!(state)
        _progress_draw!(state)
    end
    return nothing
end

"""
Advance the thin phase bar. Pass `done` to set an absolute step count; otherwise
increments by one. `label` is shown after the bar.
"""
function kit_progress_step!(label::AbstractString; done::Union{Nothing,Int}=nothing)
    state = KIT_PROGRESS[]
    state === nothing && return nothing
    if done === nothing
        state.done = min(state.done + 1, state.steps)
    else
        state.done = clamp(Int(done), 0, state.steps)
    end
    state.label = String(label)
    if kit_output_progress()
        _progress_log!(state)
        _progress_draw!(state)
    end
    return nothing
end

"""Finish the thin phase bar (newline + final color). Clears progress state."""
function kit_progress_done!(; ok::Bool=true)
    state = KIT_PROGRESS[]
    state === nothing && return nothing
    state.done = state.steps
    if isempty(state.label)
        state.label = state.title
    end
    if kit_output_progress()
        _progress_log!(state)
        _progress_draw!(state; newline=true, color=ok ? :green : :red)
    end
    KIT_PROGRESS[] = nothing
    return nothing
end

"""
Kit help chrome — every overview / `--help` starts here:

    DistSSHKit drive
    ────────────────

"""
function print_help_chrome(title::AbstractString; io::IO=stdout)
    t = String(title)
    print_help_title(t; io=io)
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
function print_help_section(msg; io=stdout)
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

print_help_blank(io::IO=stdout) = (println(io); nothing)

"""CLI user error on stderr (no stacktrace)."""
function print_cli_error(msg::AbstractString; io::IO=stderr)
    print_err("Error: "; io=io, bold=true)
    println(io, msg)
    return nothing
end

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
function print_help_document(title::AbstractString, body::AbstractString; io::IO=stdout)
    print_help_chrome(title; io=io)
    for line in split(rstrip(String(body), '\n'), '\n'; keepempty=true)
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

"""Top-level `julia -m DistSSHKit` usage (no subcommand)."""
function print_kit_root_usage(io::IO=stderr)
    print_help_chrome("DistSSHKit"; io=io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia -m DistSSHKit <command> [args...]",
    )
    print_help_blank(io)
    print_help_section("Commands"; io=io)
    print_help_lines(io,
        "  go                 Run an as-is complete job",
        "  drive              Distributed workers + collect",
        "  setup              Clone / sync / check remotes",
        "  size               Estimate worker counts",
        "  demo               Install or list example scripts",
    )
    print_help_blank(io)
    print_help_section("Examples"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit go SCRIPT.jl",
        "  julia --project=. -m DistSSHKit drive local:2 SCRIPT.jl",
        "  julia --project=. -m DistSSHKit setup --check host1",
    )
    print_help_blank(io)
    println(io, "Run `julia -m DistSSHKit <command> --help` for details.")
    return nothing
end

"""Setup-style status line (`:verbose` on terminal; otherwise kit log only)."""
ok(msg) = (write_both("  "); print_ok("✓ $msg"); writeln_both(""))
fail(msg) = (write_both("  "); print_progress_err("✗ $msg"); writeln_both(""))
warn(msg) = (write_both("  "); print_progress_warn("! $msg"); writeln_both(""))
