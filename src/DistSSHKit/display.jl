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

"""
    kit_pid_alive(pid) -> Bool

Best-effort liveness check for an OS pid (signal 0; never raises).

On Unix, `kill(pid, 0)`: alive if the call succeeds or the pid exists but is
not owned by us (`EPERM`). `pid <= 0` is false. Windows has no cheap non-killing
probe here, so the result is `true` (same for unexpected errors). For a leftover
`kit.pid` after SIGKILL, use [`kit_pid_file_running`](@ref) (pid plus start
key) so a reused number does not look like this child.
"""
function kit_pid_alive(pid::Integer)::Bool
    pid <= 0 && return false
    Sys.isunix() || return true # no cheap non-killing probe on Windows; assume alive
    try
        Base.Libc.errno(0)
        rc = ccall(:kill, Cint, (Cint, Cint), pid, 0)
        rc == 0 && return true
        return Base.Libc.errno() == Cint(1) # EPERM: pid exists, owned by someone else — still alive
    catch
        return true
    end
end

"""Linux `/proc/<pid>/stat` starttime field (clock ticks since boot), or `nothing`."""
function _linux_proc_start_key(pid::Integer)::Union{Nothing,String}
    path = string("/proc/", Int(pid), "/stat")
    isfile(path) || return nothing
    s = try
        read(path, String)
    catch
        return nothing
    end
    r = findlast(')', s)
    r === nothing && return nothing
    parts = split(SubString(s, Int(r) + 1))
    length(parts) < 20 && return nothing
    key = String(parts[20])
    return isempty(key) ? nothing : key
end

"""
    kit_process_start_key(pid) -> Union{Nothing,String}

Identity of this OS pid's start (Linux `/proc` starttime, else `ps -o lstart=`).
`nothing` if the pid is gone, unreadable, or Windows.
"""
function kit_process_start_key(pid::Integer)::Union{Nothing,String}
    pid <= 0 && return nothing
    Sys.iswindows() && return nothing
    if isfile(string("/proc/", Int(pid), "/stat"))
        return _linux_proc_start_key(pid)
    end
    try
        s = strip(read(`ps -o lstart= -p $(Int(pid))`, String))
        return isempty(s) ? nothing : s
    catch
        return nothing
    end
end

"""
    kit_output_dir_lock!(output_dir) -> release::Function

Best-effort exclusive lock on `output_dir` for the duration of one `go!` /
`drive!` run, so a caller that (mistakenly) schedules two runs into the same
`output_dir` concurrently fails fast instead of interleaving/overwriting
results — the failure mode a queue would otherwise only notice by diffing
corrupted output.

Writes `output_dir/.kit.lock` (this process's pid, plain text). An existing
lock naming a still-alive pid throws `ArgumentError` immediately. A lock
naming a dead pid is stale and gets overwritten.

Returns a zero-arg closure that releases the lock; call it in a `finally`.
Removal only happens if the file still names this process's pid (avoids
deleting a newer run's lock after, e.g., a slow filesystem or a bug).
"""
function kit_output_dir_lock!(output_dir::AbstractString)
    mkpath(output_dir)
    lock_path = joinpath(output_dir, ".kit.lock")
    mypid = getpid()
    if isfile(lock_path)
        existing = try
            strip(read(lock_path, String))
        catch
            ""
        end
        existing_pid = tryparse(Int, existing)
        if existing_pid !== nothing && existing_pid != mypid && kit_pid_alive(existing_pid)
            throw(ArgumentError(
                "another DistSSHKit run (pid $(existing_pid)) already holds " *
                "$(lock_path) — refusing to run concurrently against the same output_dir",
            ))
        end
    end
    write(lock_path, string(mypid))
    return () -> begin
        try
            if isfile(lock_path) && strip(read(lock_path, String)) == string(mypid)
                rm(lock_path; force=true)
            end
        catch
            # best-effort only
        end
    end
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

"""True when `path` is `root` or a file/dir under it."""
function _path_is_under(path::AbstractString, root::AbstractString)::Bool
    p = canonical_local_path(path)
    r = canonical_local_path(root)
    p == r && return true
    return startswith(p, r * Base.Filesystem.path_separator)
end

"""
Job root for the CLI when DistSSHKit is loaded from `kit`.

`kit` is [`kit_project_root`](@ref). If that tree is DistSSHKit's own project
(checkout, `Pkg.add` depot, or an apps env) and `cwd` is not inside it, use the
host `Project.toml` walked from `cwd`, or `cwd` if none. `DISTRIBUTED_PROJECT_ROOT`
is applied in [`cli_project_root`](@ref), not here.
"""
function _cli_job_root(kit::AbstractString, cwd::AbstractString)::String
    kit_abs = canonical_local_path(kit)
    cwd_abs = canonical_local_path(cwd)
    own_tree =
        project_package_name(kit_abs) == "DistSSHKit" &&
        !isfile(joinpath(dirname(kit_abs), "Project.toml"))
    if !own_tree
        return kit_abs
    end
    _path_is_under(cwd_abs, kit_abs) && return kit_abs
    host = resolve_pkg_project_dir(cwd_abs)
    isfile(joinpath(host, "Project.toml")) && return canonical_local_path(host)
    return cwd_abs
end

"""Local project root for kit CLI scripts (`ENV[DISTRIBUTED_PROJECT_ROOT]` or cwd / [`kit_project_root`](@ref))."""
function cli_project_root(kit_src_dir::AbstractString)
    get(ENV, "DISTRIBUTED_PROJECT_ROOT") do
        _cli_job_root(kit_project_root(kit_src_dir), pwd())
    end
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
"""`output_dir/kit.progress` path, or `nothing`. Written even when `--no-log`."""
const KIT_PROGRESS_SIDECAR = Ref{Union{Nothing,String}}(nothing)
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

"""Point `progress:` sidecar writes at `dir/kit.progress` (`nothing` clears)."""
function _set_kit_progress_sidecar!(dir::Union{Nothing,AbstractString})
    if dir === nothing
        KIT_PROGRESS_SIDECAR[] = nothing
        return nothing
    end
    d = strip(String(dir))
    isempty(d) && (KIT_PROGRESS_SIDECAR[] = nothing; return nothing)
    path = joinpath(canonical_local_path(d), "kit.progress")
    mkpath(dirname(path))
    KIT_PROGRESS_SIDECAR[] = path
    return nothing
end

function _kit_progress_sidecar_writeln(msg::AbstractString)
    path = KIT_PROGRESS_SIDECAR[]
    path === nothing && return
    try
        open(path, "a") do io
            println(io, msg)
        end
    catch
    end
    return nothing
end

function _kit_progress_sidecar_truncate!()
    path = KIT_PROGRESS_SIDECAR[]
    path === nothing && return
    try
        open(path, "w") do _
        end
    catch
    end
    return nothing
end

const KIT_JOB_STDOUT = Ref{IOBuffer}(IOBuffer())

function _reset_job_stdout_capture!()
    KIT_JOB_STDOUT[] = IOBuffer()
    return nothing
end

function _append_job_stdout_capture!(data)
    write(KIT_JOB_STDOUT[], data)
    return nothing
end

"""Replay job stdout after the live bar (`:progress` only). Always drains the buffer."""
function _print_job_stdout_after_progress!()
    s = String(take!(KIT_JOB_STDOUT[]))
    KIT_JOB_STDOUT[] = IOBuffer()
    kit_output_progress() || return nothing
    isempty(strip(s)) && return nothing
    print(stdout, s)
    endswith(s, '\n') || println(stdout)
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

# `AbstractVector{UInt8}` alone is ambiguous with Base's `write(::IO, ::StridedArray)`.
function Base.write(io::TeeIO, b::Vector{UInt8})
    bv::AbstractVector{UInt8} = b
    return _teeio_write_vector!(io, bv)
end

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

"""Print `msg` with `color` when the kit would use ANSI (TTY, no `NO_COLOR`)."""
function print_colored(io, msg, color, bold=false)
    use_colors() ? printstyled(io, msg; color=color, bold=bold) : print(io, msg)
end
const _print_colored = print_colored

function print_ok(msg; io=stdout, bold=false)
    if kit_output_detail()
        _print_colored(io, msg, :green, bold)
    end
    _kit_log_write(string(msg))
    return nothing
end

# Wait spinner (`:verbose` TTY only)

"""Frames for the kit TTY spinner (`kit_spin!`) and matching queue chrome."""
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

# Live phase progress (`--progress`)
#
# Phase mode (drive): one line. `done` is completed phases; the in-progress
# phase is `done + 1`.
# Item mode (go slots): header + one line per slot, all live. Header `done/steps`
# is completed slots; running slots keep their own spinner.

const PROGRESS_BAR_WIDTH = 20
const PROGRESS_LABEL_WIDTH = 14
const PROGRESS_FILL_CHAR = '━'
const PROGRESS_HEAD_CHAR = '╺'
const PROGRESS_EMPTY_CHAR = '━'

# Ice (sky). Dark bg uses sky-400; light bg uses sky-700.
# `DISTSSHKIT_PROGRESS_BG=dark|light` overrides `COLORFGBG`.
function _term_light_background()::Bool
    v = lowercase(strip(get(ENV, "DISTSSHKIT_PROGRESS_BG", "")))
    v == "light" && return true
    v == "dark" && return false
    fgbg = get(ENV, "COLORFGBG", "")
    m = match(r";(\d+)\s*$", fgbg)
    m === nothing && return false
    bg = tryparse(Int, m.captures[1])
    bg === nothing && return false
    return bg == 7 || bg == 15
end

function _term_truecolor()::Bool
    ct = lowercase(get(ENV, "COLORTERM", ""))
    return occursin("truecolor", ct) || occursin("24bit", ct)
end

function _progress_accent_pair()
    if _term_light_background()
        return ((3, 105, 161), 31)    # sky-700
    end
    return ((56, 189, 248), 81)       # sky-400
end

function _print_progress_accent(io::IO, x)
    if !use_colors()
        print(io, x)
        return nothing
    end
    rgb, idx = _progress_accent_pair()
    if _term_truecolor()
        r, g, b = rgb
        print(io, "\e[1;38;2;$(r);$(g);$(b)m", x, "\e[0m")
    else
        printstyled(io, x; color=idx, bold=true)
    end
    return nothing
end

mutable struct KitProgressItem
    label::String
    status::Symbol
    tick::Int
end

mutable struct KitProgressState
    title::String
    steps::Int
    done::Int
    label::String
    kind::Symbol
    active::Bool
    t0::Float64
    tick::Int
    spinning::Bool
    spinner_task::Union{Task,Nothing}
    items::Vector{KitProgressItem}
    drawn::Int
    cursor_hidden::Bool
    job_id::Union{Nothing,String}
end

function KitProgressState(
    title::AbstractString,
    steps::Int,
    done::Int,
    label::AbstractString;
    kind::Symbol=:unknown,
    job_id::Union{Nothing,AbstractString}=nothing,
)
    return KitProgressState(
        String(title),
        steps,
        done,
        String(label),
        kind,
        false,
        time(),
        0,
        false,
        nothing,
        KitProgressItem[],
        0,
        false,
        job_id === nothing ? nothing : String(job_id),
    )
end

const KIT_PROGRESS = Ref{Union{Nothing,KitProgressState}}(nothing)
const KIT_PROGRESS_LOCK = ReentrantLock()

function _progress_is_current(state::KitProgressState)::Bool
    cur = KIT_PROGRESS[]
    return cur isa KitProgressState && objectid(cur) === objectid(state)
end

function _progress_filled(done::Int, total::Int; width::Int=PROGRESS_BAR_WIDTH)::Int
    t = max(total, 1)
    return round(Int, width * clamp(done, 0, t) / t)
end

"""1-based index of the walking tip in the unfilled region, or `0` when full."""
function _progress_head_index(
    done::Int,
    total::Int,
    tick::Int;
    width::Int=PROGRESS_BAR_WIDTH,
)::Int
    filled = _progress_filled(done, total; width=width)
    filled >= width && return 0
    remaining = width - filled
    return filled + 1 + mod(max(tick, 0), remaining)
end

function _progress_bar_string(
    done::Int,
    total::Int;
    width::Int=PROGRESS_BAR_WIDTH,
    tick::Int=0,
)::String
    chars = fill(PROGRESS_FILL_CHAR, width)
    h = _progress_head_index(done, total, tick; width=width)
    h > 0 && (chars[h] = PROGRESS_HEAD_CHAR)
    return join(chars)
end

function _progress_elapsed(t0::Float64)::String
    s = max(0, round(Int, time() - t0))
    m, r = divrem(s, 60)
    m < 60 && return string(m, ":", lpad(r, 2, '0'))
    h, m2 = divrem(m, 60)
    return string(h, ":", lpad(m2, 2, '0'), ":", lpad(r, 2, '0'))
end

function _progress_current(state::KitProgressState)::Int
    isempty(state.items) || return state.done
    return state.done >= state.steps ? state.steps : state.done + 1
end

function _progress_fit_label(raw::String; width::Int=PROGRESS_LABEL_WIDTH)::String
    tw::Int = textwidth(raw)
    extra = width - tw
    extra == 0 && return raw
    extra > 0 && return raw * " "^extra
    out = Char[]
    w = 0
    ell::Int = textwidth("…")
    for c in raw
        cw::Int = textwidth(c)
        w + cw + ell > width && break
        push!(out, c)
        w += cw
    end
    return join(out) * "…" * " "^(max(0, width - w - ell))
end

function _progress_item_glyph(item::KitProgressItem)::String
    item.status === :ok && return "✓"
    item.status === :fail && return "✗"
    item.status === :running &&
        return string(SPINNER_FRAMES[mod1(item.tick, length(SPINNER_FRAMES))])
    return "·"
end

function _progress_item_color(item::KitProgressItem)::Symbol
    item.status === :ok && return :green
    item.status === :fail && return :red
    return :light_black
end

function _progress_header_label(state::KitProgressState; finished::Bool=false)::String
    use_title = finished || !isempty(state.items)
    return _progress_fit_label(use_title ? state.title : state.label)
end

function _progress_glyph(state::KitProgressState; finished::Bool=false, ok::Bool=true)::String
    finished && return ok ? "✓" : "✗"
    return string(SPINNER_FRAMES[mod1(state.tick, length(SPINNER_FRAMES))])
end

function _progress_line(
    state::KitProgressState;
    finished::Bool=false,
    ok::Bool=true,
)::String
    glyph = _progress_glyph(state; finished=finished, ok=ok)
    label = _progress_header_label(state; finished=finished)
    cur = _progress_current(state)
    elapsed = _progress_elapsed(state.t0)
    counts = "$cur/$(state.steps)"
    if finished
        return "  $glyph  $label  $counts  $elapsed"
    end
    bar = _progress_bar_string(state.done, state.steps; tick=state.tick)
    return "  $glyph  $label  $bar  $counts  $elapsed"
end

function _progress_print_header!(
    io::IO,
    state::KitProgressState;
    finished::Bool=false,
    ok::Bool=true,
)
    glyph = _progress_glyph(state; finished=finished, ok=ok)
    label = _progress_header_label(state; finished=finished)
    cur = _progress_current(state)
    counts = "$cur/$(state.steps)"
    elapsed = _progress_elapsed(state.t0)
    print(io, "  ")
    if use_colors()
        if finished
            printstyled(io, glyph; color=ok ? :green : :red)
        else
            _print_progress_accent(io, glyph)
        end
        print(io, "  ", label, "  ")
        if !finished
            _progress_print_bar!(io, state.done, state.steps, state.tick)
            print(io, "  ")
        end
        printstyled(io, counts; color=:light_black)
        print(io, "  ")
        printstyled(io, elapsed; color=:light_black)
    else
        print(io, glyph, "  ", label, "  ")
        if !finished
            print(io, _progress_bar_string(state.done, state.steps; tick=state.tick), "  ")
        end
        print(io, counts, "  ", elapsed)
    end
    return nothing
end

function _progress_draw_items!(
    state::KitProgressState;
    finished::Bool=false,
    ok::Bool=true,
)
    n = 1 + length(state.items)
    if state.drawn > 0
        print(stdout, "\e[$(state.drawn)A")
    elseif !state.cursor_hidden
        print(stdout, "\e[?25l")
        state.cursor_hidden = true
    end
    _progress_print_header!(stdout, state; finished=finished, ok=ok)
    print(stdout, "\e[K\n")
    for it in state.items
        g = _progress_item_glyph(it)
        print(stdout, "     ")
        if use_colors()
            if it.status === :running
                _print_progress_accent(stdout, g)
            else
                printstyled(stdout, g; color=_progress_item_color(it))
            end
        else
            print(stdout, g)
        end
        print(stdout, "  ", it.label, "\e[K\n")
    end
    state.drawn = n
    flush(stdout)
    return nothing
end

function _progress_draw!(
    state::KitProgressState;
    newline::Bool=false,
    finished::Bool=false,
    ok::Bool=true,
)
    !_progress_can_draw() && return nothing
    if !isempty(state.items)
        _progress_draw_items!(state; finished=finished, ok=ok)
        return nothing
    end
    print(stdout, '\r')
    _progress_print_header!(stdout, state; finished=finished, ok=ok)
    print(stdout, "\e[K")
    newline && println(stdout)
    flush(stdout)
    return nothing
end

"""Whether stdout can host a live bar (TTY and color allowed)."""
kit_stdout_is_live()::Bool = stdout isa Base.TTY && !haskey(ENV, "NO_COLOR")

_progress_can_draw()::Bool = kit_output_progress() && kit_stdout_is_live()

function _progress_stop_spinner!(state::KitProgressState)
    state.spinning || return nothing
    state.spinning = false
    t = state.spinner_task
    state.spinner_task = nothing
    t === nothing && return nothing
    task = t::Task
    if istaskstarted(task) && !istaskdone(task)
        wait(task)
    end
    return nothing
end

function _progress_spinner_tick!(state::KitProgressState)
    state.spinning || return nothing
    _progress_is_current(state) || return nothing
    state.tick += 1
    for it in state.items
        it.status === :running && (it.tick += 1)
    end
    _progress_draw!(state)
    return nothing
end

function _progress_start_spinner!(state::KitProgressState)
    (_progress_can_draw() && !state.spinning) || return nothing
    state.spinning = true
    state.spinner_task = @async begin
        while state.spinning
            _progress_is_current(state) || break
            lock(KIT_PROGRESS_LOCK) do
                _progress_spinner_tick!(state)
            end
            sleep(0.08)
        end
    end
    return nothing
end

function _progress_print_bar!(io::IO, done::Int, total::Int, tick::Int)
    width = PROGRESS_BAR_WIDTH
    filled = _progress_filled(done, total; width=width)
    head = _progress_head_index(done, total, tick; width=width)
    for i in 1:width
        if i == head
            _print_progress_accent(io, string(PROGRESS_HEAD_CHAR))
        elseif i <= filled
            _print_progress_accent(io, string(PROGRESS_FILL_CHAR))
        else
            ch = string(PROGRESS_EMPTY_CHAR)
            use_colors() ? printstyled(io, ch; color=:light_black) : print(io, ch)
        end
    end
    return nothing
end

function _progress_log_line(state::KitProgressState, event::AbstractString, kvs::Pair...)
    parts = String["progress:", String(event), "kind=$(state.kind)"]
    if state.job_id !== nothing
        push!(parts, "job=$(state.job_id)")
    end
    for (k, v) in kvs
        push!(parts, "$k=$v")
    end
    push!(parts, "t=$(round(time(); digits=3))")
    return join(parts, " ")
end

function _progress_log_writeln(
    state::KitProgressState,
    event::AbstractString,
    kvs::Pair...;
    to_log::Bool=true,
)
    line = _progress_log_line(state, event, kvs...)
    to_log && _kit_log_writeln(line)
    _kit_progress_sidecar_writeln(line)
    return nothing
end

function _progress_log_begin!(state::KitProgressState)
    _kit_progress_sidecar_truncate!()
    _progress_log_writeln(
        state,
        "begin",
        "label" => state.label,
        "total" => state.steps;
        to_log=kit_output_progress(),
    )
    return nothing
end

function _progress_log_step!(state::KitProgressState)
    _progress_log_writeln(
        state,
        "step",
        "label" => state.label,
        "done" => state.done,
        "total" => state.steps,
        "cur" => _progress_current(state);
        to_log=kit_output_progress(),
    )
    return nothing
end

"""Write a `progress: step` timing mark without changing the live bar."""
function _kit_progress_mark!(label::AbstractString)
    raw = KIT_PROGRESS[]
    raw isa KitProgressState || return nothing
    lab = String(label)
    lock(KIT_PROGRESS_LOCK) do
        _progress_is_current(raw) || return nothing
        _progress_log_writeln(
            raw,
            "step",
            "label" => lab,
            "done" => raw.done,
            "total" => raw.steps,
            "cur" => _progress_current(raw);
            to_log=kit_output_progress(),
        )
    end
    return nothing
end

"""Log an `item` span (`slot/run`, `slot/collect`) without moving the live bar."""
function _kit_progress_span!(label::AbstractString, status::Symbol)
    status in (:running, :ok, :fail) || return nothing
    raw = KIT_PROGRESS[]
    raw isa KitProgressState || return nothing
    lab = String(label)
    lock(KIT_PROGRESS_LOCK) do
        _progress_is_current(raw) || return nothing
        _progress_log_writeln(
            raw,
            "item",
            "label" => lab,
            "status" => status,
            "done" => raw.done,
            "total" => raw.steps;
            to_log=kit_output_progress(),
        )
    end
    return nothing
end

function _progress_log_item!(state::KitProgressState, item::KitProgressItem)
    _progress_log_writeln(
        state,
        "item",
        "label" => item.label,
        "status" => item.status,
        "done" => state.done,
        "total" => state.steps;
        to_log=kit_output_progress(),
    )
    return nothing
end

function _progress_log_done!(state::KitProgressState; ok::Bool)
    _progress_log_writeln(
        state,
        "done",
        "ok" => ok,
        "done" => state.done,
        "total" => state.steps,
    )
    return nothing
end

"""
    parse_progress_line(line) -> Union{Nothing,NamedTuple}

Parse one kit `progress:` log line. `nothing` if it is not that format.

Always has `event`, `kind`, `job`, `label`, `total`, `done`, `cur`,
`status`, `ok`, `t`. Missing keys are `nothing`. `event` is `:begin` / `:step` /
`:item` / `:done`. `t` is Unix time (seconds, ms in the fraction) when the
line was written.
"""
function parse_progress_line(line::AbstractString)
    s = strip(String(line))
    startswith(s, "progress:") || return nothing
    rest = strip(SubString(s, ncodeunits("progress:") + 1))
    isempty(rest) && return nothing
    tokens = split(rest; keepempty=false)
    isempty(tokens) && return nothing
    event_s = String(tokens[1])
    event_s in ("begin", "step", "item", "done") || return nothing
    event = Symbol(event_s)
    kind = nothing
    job = nothing
    label = nothing
    total = nothing
    done = nothing
    cur = nothing
    status = nothing
    ok = nothing
    t = nothing
    for tok in Iterators.drop(tokens, 1)
        tok_s = String(tok)
        eq = findfirst(==('='), tok_s)
        eq === nothing && return nothing
        k = SubString(tok_s, 1, eq - 1)
        v = SubString(tok_s, eq + 1)
        if k == "kind"
            isempty(v) && return nothing
            kind = Symbol(String(v))
        elseif k == "job"
            job = String(v)
        elseif k == "label"
            label = String(v)
        elseif k == "total"
            total = tryparse(Int, v)
            total === nothing && return nothing
        elseif k == "done"
            done = tryparse(Int, v)
            done === nothing && return nothing
        elseif k == "cur"
            cur = tryparse(Int, v)
            cur === nothing && return nothing
        elseif k == "status"
            String(v) in ("pending", "running", "ok", "fail") || return nothing
            status = Symbol(String(v))
        elseif k == "ok"
            if v == "true"
                ok = true
            elseif v == "false"
                ok = false
            else
                return nothing
            end
        elseif k == "t"
            t = tryparse(Float64, v)
            t === nothing && return nothing
        end
    end
    kind === nothing && return nothing
    return (; event, kind, job, label, total, done, cur, status, ok, t)
end

function _kit_progress_files(log_dir_or_file::AbstractString)::Vector{String}
    path = String(log_dir_or_file)
    files = String[]
    if isfile(path)
        push!(files, path)
    elseif isdir(path)
        sidecar = joinpath(path, "kit.progress")
        isfile(sidecar) && push!(files, sidecar)
        for f in readdir(path; join=true)
            isfile(f) && endswith(f, ".log") && push!(files, f)
        end
        sort!(files; by=f -> (mtime(f), f))
    end
    return files
end

function _kit_progress_records(
    log_dir_or_file::AbstractString;
    job_id::Union{Nothing,AbstractString}=nothing,
)
    files = _kit_progress_files(log_dir_or_file)
    isempty(files) && return NamedTuple[]
    want = job_id === nothing || isempty(strip(String(job_id))) ? nothing : String(strip(String(job_id)))
    recs = NamedTuple[]
    for f in files
        try
            for line in eachline(f)
                rec = parse_progress_line(line)
                rec === nothing && continue
                want !== nothing && rec.job != want && continue
                push!(recs, rec)
            end
        catch
        end
    end
    return recs
end

"""
    kit_progress_latest(log_dir_or_file; job_id=nothing) -> Union{Nothing,NamedTuple}

Last [`parse_progress_line`](@ref) hit in a kit log file, `kit.progress`,
or `*.log` under a directory (files in `mtime` order). `job_id` keeps only
`job=<id>` lines.
"""
function kit_progress_latest(
    log_dir_or_file::AbstractString;
    job_id::Union{Nothing,AbstractString}=nothing,
)
    recs = _kit_progress_records(log_dir_or_file; job_id=job_id)
    return isempty(recs) ? nothing : recs[end]
end

function _kit_progress_last_run(recs)
    isempty(recs) && return recs
    start = 1
    for i in eachindex(recs)
        recs[i].event === :begin && (start = i)
    end
    return recs[start:end]
end

"""
    kit_progress_phases(log_dir_or_file; job_id=nothing) -> Vector{NamedTuple}

Last `begin`…`done` in `kit.progress` (prefers the sidecar over `*.log`).
Each row is `label` and `seconds` (≥ 0). Sequential `step` lines are
pipeline intervals; concurrent `item` lines are per-slot spans (running→ok/fail).
CLI: `julia -m DistSSHKit progress DIR`.
"""
function kit_progress_phases(
    log_dir_or_file::AbstractString;
    job_id::Union{Nothing,AbstractString}=nothing,
)
    path = String(log_dir_or_file)
    src = if isdir(path)
        sidecar = joinpath(path, "kit.progress")
        isfile(sidecar) ? sidecar : path
    else
        path
    end
    recs = _kit_progress_last_run(_kit_progress_records(src; job_id=job_id))
    return _kit_progress_phase_rows(recs)
end

function _kit_progress_wall(recs)::Float64
    ts = Float64[r.t for r in recs if r.t !== nothing]
    isempty(ts) && return 0.0
    return max(0.0, ts[end] - ts[1])
end

function _kit_progress_item_spans(recs)
    begin_t = nothing
    t0 = Dict{String,Float64}()
    t1 = Dict{String,Float64}()
    kinds = Dict{String,Symbol}()
    order = String[]
    for r in recs
        if r.event === :begin && r.t !== nothing
            begin_t = r.t
        end
        r.event === :item || continue
        lab = r.label
        lab === nothing && continue
        r.t === nothing && continue
        haskey(t0, lab) || push!(order, lab)
        if r.status === :running || !haskey(t0, lab)
            t0[lab] = r.t
        end
        if r.status === :ok || r.status === :fail
            t1[lab] = r.t
        end
        r.kind !== nothing && (kinds[lab] = r.kind)
    end
    rows = NamedTuple[]
    for lab in order
        a = get(t0, lab, begin_t)
        b = get(t1, lab, nothing)
        a === nothing && continue
        b === nothing && continue
        dt = b - a
        dt < 0 && continue
        push!(rows, (; label=lab, seconds=dt, event=:item, kind=get(kinds, lab, :unknown)))
    end
    return rows
end

function _kit_progress_phase_rows(recs)
    item_rows = _kit_progress_item_spans(recs)
    first_item_t = nothing
    for r in recs
        if r.event === :item && r.t !== nothing
            first_item_t = first_item_t === nothing ? r.t : min(first_item_t, r.t)
        end
    end
    seq = [r for r in recs if r.event !== :item]
    rows = NamedTuple[]
    for i in 1:(length(seq) - 1)
        a = seq[i]
        b = seq[i + 1]
        a.t === nothing && continue
        b.t === nothing && continue
        a.event === :done && continue
        end_t = b.t
        if b.event === :done && first_item_t !== nothing
            end_t = first_item_t
        end
        dt = end_t - a.t
        dt < 0 && continue
        lab = if a.event === :begin
            "start"
        elseif a.label === nothing
            string(a.event)
        else
            String(a.label)
        end
        push!(rows, (; label=lab, seconds=dt, event=a.event, kind=a.kind))
    end
    append!(rows, item_rows)
    return rows
end

function _format_phase_duration(sec::Float64)::String
    if sec < 0.995
        return string(max(0, round(Int, sec * 1000)), "ms")
    end
    x = round(sec; digits=2)
    ip = trunc(Int, x)
    frac = round(Int, (x - ip) * 100 + 1e-9)
    if frac >= 100
        ip += 1
        frac = 0
    end
    return string(ip, ".", lpad(string(frac), 2, '0'), "s")
end

function _kit_progress_phase_group(label::AbstractString)
    s = String(label)
    i = findlast('/', s)
    i === nothing && return nothing
    return String(SubString(s, 1, prevind(s, i)))
end

function _kit_progress_phase_leaf(label::AbstractString)
    s = String(label)
    i = findlast('/', s)
    i === nothing && return s
    return String(SubString(s, nextind(s, i)))
end

function _kit_progress_phase_hint(
    label::AbstractString,
    event::Symbol=:step;
    indent::Int=0,
    kind::Symbol=:unknown,
)::String
    indent > 0 && label == "run" && return "script"
    indent > 0 && label == "collect" && return "pull results"
    indent > 0 && label == "workers" && return "addprocs + Julia detect"
    indent > 0 && label == "init" && return "activate project"
    indent > 0 && label == "cleanup" && return "stale workers"
    event === :item && kind === :go && return "slot"
    event === :item && return "host"
    label == "start" && return "kit"
    label == "ready" && return "remote project / Julia"
    label == "sync" && return "rsync / git deploy"
    label == "git" && return "require-git / working tree"
    label == "cleanup" && return "stale Distributed workers"
    label == "workers" && return "addprocs + Julia detect"
    label == "wait" && return "connection grace (default 5s)"
    label == "delay" && return "connection grace (default 5s)"
    label == "init" && return "using, driver sync, prepare"
    label == "run" && return "driver script"
    label == "collect" && return "gather results"
    return ""
end

function _phase_row_kind(r)::Symbol
    hasproperty(r, :kind) || return :unknown
    k = getfield(r, :kind)
    return k isa Symbol ? k : :unknown
end

function _kit_progress_display_rows(rows)
    isempty(rows) && return NamedTuple[]
    has_kids = Set{String}()
    parent_sec = Dict{String,Float64}()
    kid_sum = Dict{String,Float64}()
    for r in rows
        g = _kit_progress_phase_group(r.label)
        if g === nothing
            parent_sec[String(r.label)] = r.seconds
        else
            push!(has_kids, g)
            kid_sum[g] = get(kid_sum, g, 0.0) + r.seconds
        end
    end
    out = NamedTuple[]
    emitted = Set{String}()
    for r in rows
        g = _kit_progress_phase_group(r.label)
        if g === nothing
            String(r.label) in has_kids && continue
            push!(
                out,
                (;
                    indent=0,
                    label=String(r.label),
                    seconds=r.seconds,
                    event=r.event,
                    kind=_phase_row_kind(r),
                ),
            )
            continue
        end
        if !(g in emitted)
            sec = get(parent_sec, g, get(kid_sum, g, 0.0))
            push!(out, (; indent=0, label=g, seconds=sec, event=:item, kind=_phase_row_kind(r)))
            push!(emitted, g)
        end
        push!(
            out,
            (;
                indent=2,
                label=_kit_progress_phase_leaf(r.label),
                seconds=r.seconds,
                event=r.event,
                kind=_phase_row_kind(r),
            ),
        )
    end
    return out
end

function _phase_share_filled(sec::Float64, peak::Float64; width::Int=PROGRESS_BAR_WIDTH)::Int
    peak <= 0 && return 0
    n = round(Int, width * sec / peak)
    sec > 0 && n == 0 && (n = 1)
    return clamp(n, 0, width)
end

function _phase_share_bar(sec::Float64, peak::Float64; width::Int=PROGRESS_BAR_WIDTH)::String
    n = _phase_share_filled(sec, peak; width=width)
    return rpad(repeat("█", n), width)
end

function _print_phase_share_bar!(io::IO, sec::Float64, peak::Float64; width::Int=PROGRESS_BAR_WIDTH)
    n = _phase_share_filled(sec, peak; width=width)
    n > 0 && _print_progress_accent(io, repeat("█", n))
    rest = width - n
    rest == 0 && return nothing
    if use_colors()
        printstyled(io, repeat("░", rest); color=:light_black)
    else
        print(io, " "^rest)
    end
    return nothing
end

function _format_kit_progress_phases(
    rows;
    wall::Union{Nothing,Float64}=nothing,
)::String
    disp = _kit_progress_display_rows(rows)
    isempty(disp) && return ""
    summed = sum(r -> r.seconds, rows; init=0.0)
    total_sec = wall === nothing || wall <= 0 ? summed : Float64(wall)
    peak = maximum(r -> r.seconds, disp)
    shown = String[" "^r.indent * r.label for r in disp]
    lab_w = maximum(length, shown)
    durs = [_format_phase_duration(r.seconds) for r in disp]
    dur_w = max(maximum(length, durs), length(_format_phase_duration(total_sec)))
    buf = IOBuffer()
    println(buf, "  Time  ", _format_phase_duration(total_sec))
    println(buf)
    for (r, dur, shown_lab) in zip(disp, durs, shown)
        pct = total_sec > 0 ? round(Int, 100 * r.seconds / total_sec) : 0
        hint = _kit_progress_phase_hint(
            r.label, r.event; indent=r.indent, kind=_phase_row_kind(r),
        )
        print(
            buf,
            "    ",
            rpad(shown_lab, lab_w),
            "  ",
            lpad(dur, dur_w),
            "  ",
            _phase_share_bar(r.seconds, peak),
            "  ",
            lpad(string(pct), 3),
            "%",
        )
        isempty(hint) || print(buf, "  ", hint)
        println(buf)
    end
    return String(take!(buf))
end

function _print_kit_progress_phases(
    io::IO,
    rows;
    wall::Union{Nothing,Float64}=nothing,
)
    isempty(rows) && return nothing
    if !(io isa Base.TTY && use_colors())
        print(io, _format_kit_progress_phases(rows; wall=wall))
        return nothing
    end
    disp = _kit_progress_display_rows(rows)
    isempty(disp) && return nothing
    summed = sum(r -> r.seconds, rows; init=0.0)
    total_sec = wall === nothing || wall <= 0 ? summed : Float64(wall)
    peak = maximum(r -> r.seconds, disp)
    shown = String[" "^r.indent * r.label for r in disp]
    lab_w = maximum(length, shown)
    durs = [_format_phase_duration(r.seconds) for r in disp]
    dur_w = max(maximum(length, durs), length(_format_phase_duration(total_sec)))
    print(io, "  ")
    _print_progress_accent(io, "Time")
    printstyled(io, "  ", _format_phase_duration(total_sec); color=:light_black)
    println(io)
    println(io)
    for (r, dur, shown_lab) in zip(disp, durs, shown)
        pct = total_sec > 0 ? round(Int, 100 * r.seconds / total_sec) : 0
        hint = _kit_progress_phase_hint(
            r.label, r.event; indent=r.indent, kind=_phase_row_kind(r),
        )
        print(io, "    ", rpad(shown_lab, lab_w), "  ", lpad(dur, dur_w), "  ")
        _print_phase_share_bar!(io, r.seconds, peak)
        printstyled(io, "  ", lpad(string(pct), 3), "%"; color=:light_black)
        isempty(hint) || printstyled(io, "  ", hint; color=:light_black)
        println(io)
    end
    return nothing
end

"""Print phase wall times from `kit.progress` (`:progress` / `:verbose` only)."""
function _maybe_print_kit_progress_phases(dir::AbstractString)
    _print_job_stdout_after_progress!()
    kit_output_quiet() && return nothing
    recs = _kit_progress_last_run(_kit_progress_records(dir))
    rows = _kit_progress_phase_rows(recs)
    wall = _kit_progress_wall(recs)
    text = String(rstrip(_format_kit_progress_phases(rows; wall=wall)))
    isempty(text) && return nothing
    replay = "  progress  $(dir)"
    if kit_output_progress()
        _print_kit_progress_phases(stdout, rows; wall=wall)
        println(stdout, replay)
        _kit_log_writeln(text)
        _kit_log_writeln(String(strip(replay)))
    else
        writeln_both(text)
        writeln_both(String(strip(replay)))
    end
    return nothing
end

function show_progress_usage(io::IO=stdout)
    print_help_chrome("DistSSHKit progress"; io=io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia -m DistSSHKit progress [DIR]",
    )
    print_help_blank(io)
    print_help_section("Args"; io=io)
    print_help_lines(io,
        "  DIR   output_dir (reads kit.progress) or a kit.progress / *.log file",
        "        default: current directory",
    )
    print_help_blank(io)
    println(io, "Last run in kit.progress: phase share of wall time.")
    return nothing
end

"""
    progress(args=ARGS) -> Cint

CLI: print [`kit_progress_phases`](@ref) for `DIR` / `kit.progress`.
"""
function progress(args::Vector{String}=copy(ARGS))::Cint
    if !isempty(args) && args[1] in ("-h", "--help", "help")
        show_progress_usage()
        return 0
    end
    if length(args) > 1
        print_cli_error("progress: extra args $(repr(args[2:end]))")
        return 1
    end
    target = isempty(args) ? pwd() : String(args[1])
    recs = _kit_progress_last_run(_kit_progress_records(target))
    if isempty(recs)
        print_cli_error("progress: no progress: lines in $(target)")
        return 1
    end
    rows = _kit_progress_phase_rows(recs)
    wall = _kit_progress_wall(recs)
    text = _format_kit_progress_phases(rows; wall=wall)
    isempty(text) && (print_cli_error("progress: no timed phases in $(target)"); return 1)
    _print_kit_progress_phases(stdout, rows; wall=wall)
    return 0
end

"""
Start a live status line for `--progress` mode.

`steps` is the total number of phases or slots. Pass `items` for concurrent
slots (header + one live line each). Items start `:pending` until
[`kit_progress_item!`](@ref) sets `:running`. Outside `:progress`, updates state
only.

`kind` is `:go` or `:drive` (written as `kind=` on every `progress:` log
line). `job_id` (default: `ENV["DISTSSHKIT_JOB_ID"]` if set, else `nothing`)
is written as `job=<id>` on those lines, omitted when unset.
"""
function kit_progress_begin!(
    title::AbstractString;
    steps::Int,
    items::AbstractVector{<:AbstractString}=String[],
    kind::Symbol=:unknown,
    job_id::Union{Nothing,AbstractString}=nothing,
)
    steps < 1 && throw(ArgumentError("kit_progress_begin!: steps must be ≥ 1"))
    prev = KIT_PROGRESS[]
    prev isa KitProgressState && _progress_stop_spinner!(prev)
    _reset_job_stdout_capture!()
    resolved_job_id = job_id
    if resolved_job_id === nothing
        env_job_id = get(ENV, "DISTSSHKIT_JOB_ID", "")
        isempty(env_job_id) || (resolved_job_id = env_job_id)
    end
    state = KitProgressState(
        String(title), steps, 0, String(title); kind=kind, job_id=resolved_job_id,
    )
    for name in items
        push!(state.items, KitProgressItem(String(name), :pending, 0))
    end
    lock(KIT_PROGRESS_LOCK) do
        KIT_PROGRESS[] = state
        _progress_log_begin!(state)
        if kit_output_progress()
            _progress_draw!(state)
        end
    end
    kit_output_progress() && _progress_start_spinner!(state)
    return nothing
end

"""
Set the in-progress label.

The first call does not increment `done`. Later calls mark the previous phase
complete (`done += 1`) then switch the label. Pass `done` to set completed
count absolutely (in-progress is still `done + 1` until [`kit_progress_done!`](@ref)).
"""
function kit_progress_step!(label::AbstractString; done::Union{Nothing,Int}=nothing)
    raw = KIT_PROGRESS[]
    raw isa KitProgressState || return nothing
    _kit_progress_step!(raw, label; done)
    return nothing
end

function _kit_progress_step!(
    state::KitProgressState,
    label::AbstractString;
    done::Union{Nothing,Int},
)
    lock(KIT_PROGRESS_LOCK) do
        _progress_is_current(state) || return nothing
        if done === nothing
            if state.active
                state.done = min(state.done + 1, state.steps)
            end
            state.active = true
        else
            d = done::Int
            state.done = clamp(d, 0, state.steps)
            state.active = true
        end
        state.label = String(label)
        _progress_log_step!(state)
        if kit_output_progress()
            _progress_draw!(state)
        end
    end
    kit_output_progress() && _progress_start_spinner!(state)
    return nothing
end

"""
Update one concurrent item (`:running` / `:ok` / `:fail`). Completing an item
(`:ok` or `:fail`) increments `done` once.
"""
function kit_progress_item!(label::AbstractString; status::Symbol)
    status in (:pending, :running, :ok, :fail) ||
        throw(ArgumentError("kit_progress_item!: status must be :pending, :running, :ok, or :fail"))
    raw = KIT_PROGRESS[]
    raw isa KitProgressState || return nothing
    _kit_progress_item!(raw, label, status)
    return nothing
end

function _kit_progress_apply_item!(
    item::KitProgressItem,
    state::KitProgressState,
    status::Symbol,
)
    prev = item.status
    item.status = status
    if (status === :ok || status === :fail) && prev !== :ok && prev !== :fail
        state.done = min(state.done + 1, state.steps)
    end
    _progress_log_item!(state, item)
    if kit_output_progress()
        _progress_draw!(state)
    end
    return nothing
end

function _kit_progress_item!(state::KitProgressState, label::AbstractString, status::Symbol)
    lock(KIT_PROGRESS_LOCK) do
        _progress_is_current(state) || return nothing
        target = String(label)
        for it in state.items
            if it.label == target
                _kit_progress_apply_item!(it, state, status)
                break
            end
        end
        return nothing
    end
    kit_output_progress() && _progress_start_spinner!(state)
    return nothing
end

"""
Finish the status line (newline, ✓/✗, elapsed; no track). Optional `footer`
prints under the line (`:progress` only; also kit log). Clears progress state.
"""
function kit_progress_done!(; ok::Bool=true, footer::Union{Nothing,AbstractString}=nothing)
    raw = KIT_PROGRESS[]
    raw isa KitProgressState || return nothing
    _kit_progress_done!(raw; ok=ok, footer=footer)
    return nothing
end

function _kit_progress_done!(
    state::KitProgressState;
    ok::Bool,
    footer::Union{Nothing,AbstractString},
)
    _progress_stop_spinner!(state)
    lock(KIT_PROGRESS_LOCK) do
        _progress_is_current(state) || return nothing
        state.done = state.steps
        state.label = state.title
        _progress_log_done!(state; ok=ok)
        if kit_output_progress()
            _progress_draw!(state; newline=true, finished=true, ok=ok)
            if state.cursor_hidden
                print(stdout, "\e[?25h")
                state.cursor_hidden = false
            end
            _progress_print_footer(footer)
        end
        KIT_PROGRESS[] = nothing
    end
    return nothing
end

_progress_print_footer(::Nothing) = nothing
function _progress_print_footer(footer::AbstractString)
    s = String(footer)
    isempty(s) && return nothing
    note = "     $s"
    println(stdout, note)
    _kit_log_writeln(rstrip(note))
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

"""One blank line in kit `--help` output."""
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
        "  progress           Phase seconds from kit.progress",
    )
    print_help_blank(io)
    print_help_section("Examples"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit go SCRIPT.jl",
        "  julia --project=. -m DistSSHKit drive parenthost:2 SCRIPT.jl",
        "  julia --project=. -m DistSSHKit setup --check host1",
    )
    print_help_blank(io)
    println(io, "Run `julia -m DistSSHKit <command> -h` for flags.")
    return nothing
end

"""Setup-style status line (`:verbose` on terminal; otherwise kit log only)."""
ok(msg) = (write_both("  "); print_ok("✓ $msg"); writeln_both(""))
fail(msg) = (write_both("  "); print_progress_err("✗ $msg"); writeln_both(""))
warn(msg) = (write_both("  "); print_progress_warn("! $msg"); writeln_both(""))
