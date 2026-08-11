# Bundled demos under `demos/with_kit/` and `demos/without_kit/` (`demo install` / `demo list`).

const _DEMO_GROUPS = ("with_kit", "without_kit")

"""Package `demos/` root (with_kit + without_kit)."""
demos_root()::String = joinpath(_KIT_ROOT, "demos")

"""Same as [`demos_root`](@ref) — installable demo tree."""
demos_dir()::String = demos_root()

"""Relative demo ids such as `with_kit/square_file`, sorted."""
function list_demos()::Vector{String}
    root = demos_root()
    names = String[]
    for group in _DEMO_GROUPS
        dir = joinpath(root, group)
        isdir(dir) || continue
        for entry in readdir(dir)
            endswith(entry, ".jl") || continue
            push!(names, group * "/" * replace(basename(entry), ".jl" => ""))
        end
    end
    return sort(names)
end

"""
    demo_script(name) -> Union{String, Nothing}

Absolute path to a bundled demo. `name` may be `with_kit/square_file`,
`square_file`, or `square_file.jl`. Bare names search `with_kit/` then `without_kit/`.
Returns `nothing` when no such demo exists.
"""
function demo_script(name::AbstractString)::Union{Nothing,String}
    s = String(name)
    endswith(s, ".jl") && (s = s[1:(end - 3)])
    if occursin('/', s)
        path = joinpath(demos_root(), s * ".jl")
        return isfile(path) ? abspath(path) : nothing
    end
    base = basename(s)
    for group in _DEMO_GROUPS
        path = joinpath(demos_root(), group, base * ".jl")
        isfile(path) && return abspath(path)
    end
    return nothing
end

"""
    install_demos(dest=pwd(); force=false) -> (installed=Vector{String}, skipped=Vector{String})

Copy bundled demos into `joinpath(dest, "demos")`, preserving `with_kit/` and
`without_kit/`. Also copies `demos/.gitignore` when present.

By default, existing files at the destination are left alone — pass `force=true` to
overwrite them.

Refuses to install into this package's own `demos/` tree (would overwrite the kit).
Use `demo list` or `demo install --dest DIR` instead.
"""
function install_demos(dest::AbstractString=pwd(); force::Bool=false)
    src_root::String = demos_root()
    isdir(src_root) || return (installed=String[], skipped=String[])
    dest_root = canonical_local_path(dest)
    dest_demos = joinpath(dest_root, "demos")
    kit_demos = abspath(src_root)
    if abspath(dest_demos) == kit_demos
        throw(ArgumentError(
            "destination would be the package's bundled demos tree ($kit_demos); " *
            "use `demo list` to see paths, or `demo install --dest DIR` to copy elsewhere",
        ))
    end
    mkpath(dest_demos)
    installed = String[]
    skipped = String[]
    for group in _DEMO_GROUPS
        src_dir::String = joinpath(src_root, group)
        isdir(src_dir) || continue
        dest_group::String = joinpath(dest_demos, group)
        mkpath(dest_group)
        for entry in sort(readdir(src_dir)::Vector{String})
            endswith(entry, ".jl") || continue
            from = abspath(joinpath(src_dir, entry))
            out = abspath(joinpath(dest_group, entry))
            if !force && isfile(out)
                push!(skipped, out)
                continue
            end
            cp(from, out; force=true)
            push!(installed, out)
        end
    end
    gitignore = joinpath(src_root, ".gitignore")
    if isfile(gitignore)
        gitignore_out = joinpath(dest_demos, ".gitignore")
        if !force && isfile(gitignore_out)
            push!(skipped, gitignore_out)
        else
            cp(gitignore, gitignore_out; force=true)
        end
    end
    return (installed=installed, skipped=skipped)
end

function _demo_install_args(args::Vector{String})::@NamedTuple{dest::String, force::Bool}
    dest = canonical_local_path(get(ENV, "DISTRIBUTED_PROJECT_ROOT", pwd()))
    force = false
    c = CliCursor(args)
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if arg == "--dest"
            dest = canonical_local_path(cli_take_value!(c, arg))
        elseif arg == "--force"
            force = true
            cli_consume!(c)
        else
            throw(ArgumentError("unknown option: $arg (supported: --dest DIR, --force)"))
        end
    end
    return (dest=dest, force=force)
end

function show_demo_usage(io::IO=stdout)
    print_help_chrome("DistSSHKit demo"; io=io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit demo install [--dest DIR] [--force]",
        "  julia --project=. -m DistSSHKit demo list",
    )
    print_help_blank(io)
    print_help_section("Commands"; io=io)
    print_help_lines(io,
        "  install  Copy demos/with_kit/ and demos/without_kit/ into ./demos/",
        "           (existing files left alone; --force overwrites).",
        "  list     Show demo ids and package paths.",
    )
    print_help_blank(io)
    print_help_section("Layout"; io=io)
    print_help_lines(io,
        "  with_kit/     DistSSHKit drivers (drive / pipeline!)",
        "  without_kit/  Kit-independent scripts (julia / go)",
    )
    print_help_blank(io)
    print_help_section("Demos (demo install)"; io=io)
    for name in list_demos()
        println(io, "  $name")
    end
    print_help_blank(io)
    print_help_section("Options"; io=io)
    print_help_lines(io,
        "  --dest DIR   Install under DIR/demos/ (default: ./demos/)",
        "  --force      Overwrite existing demo files",
        "  -h, --help   Show this help",
    )
    print_help_blank(io)
    print_help_section("After install"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl",
        "  julia --project=. demos/with_kit/pipeline_square.jl",
        "  julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl",
    )
    return nothing
end

"""
    demo(args::Vector{String}=copy(ARGS))

Install or list bundled demos. See [`(@main)`](@ref).

    julia --project=. -m DistSSHKit demo install
    julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
    julia --project=. demos/with_kit/pipeline_square.jl
"""
function demo(args::Vector{String}=copy(ARGS))::Cint
    if isempty(args) || args[1] in ("-h", "--help", "help")
        show_demo_usage()
        return 0
    end
    sub, rest = args[1], args[2:end]
    if sub == "list"
        for name in list_demos()
            path = demo_script(name)
            path === nothing && continue
            println(name, "\t", path)
        end
        return 0
    elseif sub == "install"
        try
            dest, force = _demo_install_args(rest)
            if isempty(list_demos())
                print_cli_error("No demo scripts found in package ($(demos_dir()))")
                return 1
            end
            result = install_demos(dest; force=force)
            for path in result.installed
                println("wrote ", path)
            end
            for path in result.skipped
                println("skipped (already exists, use --force to overwrite): ", path)
            end
            dest_demos = joinpath(dest, "demos")
            rel_demos = relpath(dest_demos, dest)
            println()
            println("Demos are in ", dest_demos, "; open and edit them, then run for example:")
            println("  julia --project=. -m DistSSHKit drive local:2 $rel_demos/with_kit/square_file.jl")
            println("  julia --project=. -m DistSSHKit go $rel_demos/without_kit/pi_file.jl")
            return 0
        catch err
            print_cli_error(sprint(showerror, err))
            return 1
        end
    else
        print_cli_error("Unknown demo command: $sub (try: demo install, demo list, demo --help)")
        return 1
    end
end
