# Argument parsing for `plan` (inspect only; optional size via `size!`).

function _plan_parsed(;
    show_help::Bool,
    show_version::Bool,
    cli_session,
    script_path,
    tokens::Vector{String}=String[],
    gb_per_worker=nothing,
    probe=nothing,
    mem_headroom::Float64=DEFAULT_MEM_HEADROOM,
    parent_gb::Float64=DEFAULT_PARENT_GB,
)
    return (
        show_help=show_help,
        show_version=show_version,
        cli_session=cli_session,
        script_path=script_path,
        tokens=tokens,
        gb_per_worker=gb_per_worker,
        probe=probe,
        mem_headroom=mem_headroom,
        parent_gb=parent_gb,
    )
end

function show_plan_usage(; io::IO=stdout)
    print_help_chrome("DistSSHKit plan"; io=io)
    print_help_lines(io,
        "Inspect a script. Does not start a job.",
        "Suggests go, ride, or drive from syntax (map / filter / comprehension /",
        "independent indexed for; other for is out of scope; Distributed → drive).",
        "Optional slot estimate calls size! (off unless hosts / --gb-per-worker / --probe).",
    )
    print_help_blank(io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit plan SCRIPT.jl",
        "  plan SCRIPT.jl",
        "  plan parent --gb-per-worker 1.5 SCRIPT.jl",
    )
    print_help_blank(io)
    print_help_section("Options"; io=io)
    print_help_lines(io,
        "  parent[:N] / child:NAME[:N]  hosts for optional size! (`:N` ignored)",
        "  --gb-per-worker N   skip RSS; assume N GB each (runs size!)",
        "  --probe PATH        warm-up script; peak RSS (runs size!)",
        "  --mem-headroom N    RAM fraction (default $(DEFAULT_MEM_HEADROOM))",
        "  --parent-gb N       parent process reserve (default $(DEFAULT_PARENT_GB))",
        "  $(KIT_HOSTS_FLAG_HELP)",
        "  --hosts-file PATH   one token per line",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank(io)
    print_help_lines(io,
        "See also: go, ride, drive, size.",
        "API: plan(script; workers=, gb_per_worker=, probe=) (no bang).",
    )
    return nothing
end

function parse_plan_args(args::Vector{String})
    cli_session, args = peel_kit_cli_flags(args)
    script_path = nothing
    tokens = String[]
    gb_per_worker = nothing
    probe = nothing
    mem_headroom = DEFAULT_MEM_HEADROOM
    parent_gb = DEFAULT_PARENT_GB
    c = CliCursor(args)
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if cli_match(c, ["-h", "--help"])
            cli_consume!(c)
            return _plan_parsed(;
                show_help=true,
                show_version=cli_session.show_version,
                cli_session=cli_session,
                script_path=script_path,
                tokens=tokens,
                gb_per_worker=gb_per_worker,
                probe=probe,
                mem_headroom=mem_headroom,
                parent_gb=parent_gb,
            )
        elseif arg == "--gb-per-worker"
            gb_per_worker = parse(Float64, cli_take_value!(c, arg))
        elseif arg == "--probe"
            probe = String(cli_take_value!(c, arg))
        elseif arg == "--mem-headroom"
            mem_headroom = parse(Float64, cli_take_value!(c, arg))
        elseif arg == "--parent-gb"
            parent_gb = parse(Float64, cli_take_value!(c, arg))
        elseif startswith(arg, "-")
            @warn "Unknown option: $arg"
            cli_consume!(c)
        elseif endswith(arg, ".jl")
            script_path === nothing || throw(ArgumentError(
                "plan accepts one SCRIPT.jl, got $(repr(script_path)) and $(repr(arg))",
            ))
            script_path = arg
            cli_consume!(c)
        else
            parse_placement_token(arg)
            push!(tokens, arg)
            cli_consume!(c)
        end
    end
    append_kit_host_sources!(tokens, cli_session; keep_counts=true, roles=true)
    apply_kit_cli_session!(cli_session)
    return _plan_parsed(;
        show_help=false,
        show_version=cli_session.show_version,
        cli_session=cli_session,
        script_path=script_path,
        tokens=tokens,
        gb_per_worker=gb_per_worker,
        probe=probe,
        mem_headroom=mem_headroom,
        parent_gb=parent_gb,
    )
end
