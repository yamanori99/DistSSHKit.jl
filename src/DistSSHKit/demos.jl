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

"""Relative path under `project_root/demos/`, or `nothing` if outside that tree."""
function _relpath_under_project_demos(
    script_path::AbstractString,
    project_root::AbstractString,
)::Union{Nothing,String}
    root = abspath(String(project_root))
    path = abspath(String(script_path))
    demos = joinpath(root, "demos")
    path == demos && return "."
    prefix = demos * Base.Filesystem.path_separator
    startswith(path, prefix) || return nothing
    return relpath(path, demos)
end

# Demo-domain diagnose/explain (shared surface helpers: `explain.jl`).

function _demo_install_phrase(
    surface::Symbol;
    family::Union{Nothing,AbstractString}=nothing,
)::String
    fam = family === nothing ? nothing : String(family)
    if _normalize_hint_surface(surface) === :api
        fam === nothing && return "`DistSSHKit.install_demos(; family=\"with_kit\")`"
        return "`DistSSHKit.install_demos(; family=$(repr(fam)))`"
    end
    fam === nothing && return "`julia --project=. -m DistSSHKit demo install with_kit`"
    return "`julia --project=. -m DistSSHKit demo install $fam`"
end

function _demo_list_phrase(surface::Symbol)::String
    _normalize_hint_surface(surface) === :api && return "`DistSSHKit.list_demos()`"
    return "`julia --project=. -m DistSSHKit demo list`"
end

"""
Facts about a missing script path when a demo-related tip applies.

Returns `nothing`, or a NamedTuple with `kind`:
- `:use_path` — file already at `demos/<group>/<name>`
- `:install_bundled` — basename matches a package demo
- `:demos_tree_missing` — path under `./demos/` but that tree is absent
- `:demos_file_missing` — under `./demos/` but this file is absent

Keep diagnosis free of CLI/API wording; [`explain_missing_script_hint`](@ref) formats.
"""
function diagnose_missing_script(
    script_path::AbstractString,
    project_root::AbstractString,
)::Union{Nothing,@NamedTuple{kind::Symbol, group::Union{Nothing,String}, name::Union{Nothing,String}}}
    path = String(script_path)
    root = String(project_root)
    base = basename(path)
    if endswith(base, ".jl")
        for group in _DEMO_GROUPS
            installed = joinpath(root, "demos", group, base)
            if isfile(installed)
                return (kind=:use_path, group=String(group), name=base)
            end
        end
        bundled = demo_script(base)
        if bundled !== nothing
            group = basename(dirname(bundled))
            return (kind=:install_bundled, group=group, name=base)
        end
    end
    under = _relpath_under_project_demos(path, root)
    under === nothing && return nothing
    demos_dir = joinpath(abspath(root), "demos")
    if !isdir(demos_dir)
        return (kind=:demos_tree_missing, group=nothing, name=endswith(base, ".jl") ? base : nothing)
    end
    return (kind=:demos_file_missing, group=nothing, name=endswith(base, ".jl") ? base : nothing)
end

"""Render a [`diagnose_missing_script`](@ref) result for `:cli` or `:api`."""
function explain_missing_script_hint(
    diag::NamedTuple;
    surface::Symbol=:cli,
)::String
    surface = _normalize_hint_surface(surface)
    fam = diag.group
    install = _demo_install_phrase(surface; family=fam)
    list = _demo_list_phrase(surface)
    kind = diag.kind
    if kind === :use_path
        return "Hint: use demos/$(diag.group)/$(diag.name)"
    elseif kind === :install_bundled
        return "Hint: run $install to copy that family into ./demos/, then use demos/$(diag.group)/$(diag.name)"
    elseif kind === :demos_tree_missing
        return "Hint: ./demos/ is missing — run $install first, or create this script under demos/"
    elseif kind === :demos_file_missing
        return "Hint: no such file under ./demos/ — run $install / $list, or check the script name"
    end
    throw(ArgumentError("unknown missing-script diagnosis kind: $(repr(kind))"))
end

"""
Optional one-line hint when a script path is missing (forgot demo install,
wrong `demos/` layout, etc.). Returns `nothing` when no demo-related tip applies.

`surface` is `:cli` (default) or `:api` — only the suggested next command changes.
"""
function missing_script_demo_hint(
    script_path::AbstractString,
    project_root::AbstractString;
    surface::Symbol=:cli,
)::Union{Nothing,String}
    diag = diagnose_missing_script(script_path, project_root)
    diag === nothing && return nothing
    return explain_missing_script_hint(diag; surface=surface)
end

function _require_demo_family(family::Union{Nothing,AbstractString}; surface::Symbol=:api)::String
    fam = family === nothing ? "" : String(family)
    fam in _DEMO_GROUPS && return fam
    names = join(_DEMO_GROUPS, " or ")
    if _normalize_hint_surface(surface) === :api
        throw(ArgumentError(
            "install_demos requires family=$names; got $(repr(family))",
        ))
    end
    throw(ArgumentError(
        "demo install requires $names (got $(family === nothing ? "none" : repr(fam)))",
    ))
end

"""
    install_demos(dest=pwd(); family, force=false) -> (installed=Vector{String}, skipped=Vector{String})

Copy one bundled family (`with_kit` or `without_kit`) into `joinpath(dest, "demos")`.
Also copies `demos/.gitignore` when present.

By default, existing files at the destination are left alone — pass `force=true` to
overwrite them.

Refuses to install into this package's own `demos/` tree (would overwrite the kit).
Use [`list_demos`](@ref) / `demo list`, or install with an explicit `dest` / `--dest`.
"""
function install_demos(
    dest::AbstractString=pwd();
    family::Union{Nothing,AbstractString}=nothing,
    force::Bool=false,
    surface::Symbol=:api,
)
    group = _require_demo_family(family; surface=surface)
    src_root::String = demos_root()
    isdir(src_root) || return (installed=String[], skipped=String[])
    dest_root = canonical_local_path(dest)
    dest_demos = joinpath(dest_root, "demos")
    kit_demos = abspath(src_root)
    if abspath(dest_demos) == kit_demos
        list = _demo_list_phrase(surface)
        install = if _normalize_hint_surface(surface) === :api
            "`DistSSHKit.install_demos(dest=...; family=$(repr(group)))`"
        else
            "`julia --project=. -m DistSSHKit demo install $group --dest DIR`"
        end
        throw(ArgumentError(
            "destination would be the package's bundled demos tree ($kit_demos); " *
            "use $list to see paths, or $install to copy elsewhere",
        ))
    end
    mkpath(dest_demos)
    installed = String[]
    skipped = String[]
    src_dir::String = joinpath(src_root, group)
    if isdir(src_dir)
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

function _demo_install_args(
    args::Vector{String},
)::@NamedTuple{dest::String, force::Bool, family::String}
    dest = canonical_local_path(get(ENV, "DISTRIBUTED_PROJECT_ROOT", pwd()))
    force = false
    families = String[]
    c = CliCursor(args)
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if arg == "--dest"
            dest = canonical_local_path(cli_take_value!(c, arg))
        elseif arg == "--force"
            force = true
            cli_consume!(c)
        elseif startswith(arg, "-")
            throw(ArgumentError("unknown option: $arg (supported: --dest DIR, --force)"))
        else
            push!(families, arg)
            cli_consume!(c)
        end
    end
    length(families) > 1 && throw(ArgumentError(
        "demo install takes one family (with_kit or without_kit); got extra $(repr(families[2]))",
    ))
    fam = _require_demo_family(isempty(families) ? nothing : families[1]; surface=:cli)
    return (dest=dest, force=force, family=fam)
end

function show_demo_usage(io::IO=stdout)
    print_help_chrome("DistSSHKit demo"; io=io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit demo install with_kit [--dest DIR] [--force]",
        "  julia --project=. -m DistSSHKit demo install without_kit [--dest DIR] [--force]",
        "  julia --project=. -m DistSSHKit demo list",
    )
    print_help_blank(io)
    print_help_section("Commands"; io=io)
    print_help_lines(io,
        "  install FAMILY  Copy demos/FAMILY/ into ./demos/ (with_kit or without_kit).",
        "                  Existing files left alone; --force overwrites. Not both families.",
        "  list            Show demo ids and package paths.",
    )
    print_help_blank(io)
    print_help_section("Layout"; io=io)
    print_help_lines(io,
        "  with_kit/     DistSSHKit drivers (drive / pipeline!)",
        "  without_kit/  Kit-independent scripts (julia / go / go!)",
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
        "  julia --project=. demos/without_kit/pipeline_pi.jl",
        "  julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl",
    )
    return nothing
end

"""
    demo(args::Vector{String}=copy(ARGS))

Install or list bundled demos. See [`(@main)`](@ref).

    julia --project=. -m DistSSHKit demo install with_kit
    julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
    julia --project=. demos/with_kit/pipeline_square.jl
    julia --project=. demos/without_kit/pipeline_pi.jl
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
            dest, force, family = _demo_install_args(rest)
            if isempty(list_demos())
                print_cli_error("No demo scripts found in package ($(demos_dir()))")
                return 1
            end
            result = install_demos(dest; family=family, force=force, surface=:cli)
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
            if family == "with_kit"
                println("  julia --project=. -m DistSSHKit drive local:2 $rel_demos/with_kit/square_file.jl")
                println("  julia --project=. $rel_demos/with_kit/pipeline_square.jl")
            else
                println("  julia --project=. $rel_demos/without_kit/pipeline_pi.jl")
                println("  julia --project=. -m DistSSHKit go $rel_demos/without_kit/pi_file.jl")
            end
            return 0
        catch err
            print_cli_error(sprint(showerror, err))
            return 1
        end
    else
        print_cli_error("Unknown demo command: $sub (try: demo install with_kit, demo list, demo --help)")
        return 1
    end
end
