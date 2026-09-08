# Argument parsing for `ride` (run-only; analysis is `plan`).

function _ride_parsed(;
        help::Bool,
        show_version,
        cli_session,
        script_path,
        script_args,
        hosts,
        spi_check::Bool,
        output_dir,
        julia = nothing,
    )
    return (
        help = help,
        show_version = show_version,
        cli_session = cli_session,
        script_path = script_path,
        script_args = script_args,
        hosts = hosts,
        spi_check = spi_check,
        output_dir = output_dir,
        julia = julia,
    )
end

function show_ride_usage(; io::IO = stdout)
    print_help_chrome("DistSSHKit ride"; io = io)
    print_help_lines(
        io,
        "Experimental. Split map / filter / simple comprehensions / indexed for",
        "on Distributed workers.",
        "Does not analyze (see plan). Rejects Distributed vocabulary (use drive).",
        "SSH child: uses the same worker-add path as drive (setup the project first).",
    )
    print_help_blank(io)
    print_help_section("Usage"; io = io)
    print_help_lines(
        io,
        "  julia --project=. -m DistSSHKit ride SCRIPT.jl",
        "  ride parent:2 SCRIPT.jl",
        "  ride parent:1 child:host1:2 SCRIPT.jl",
        "  ride --no-spi-check parent:2 SCRIPT.jl",
    )
    print_help_blank(io)
    print_help_section("Options"; io = io)
    print_help_lines(
        io,
        "  parent:N / child:NAME:N  Distributed workers (default: no tokens → parent:1)",
        "  omit :N             error (use size, then paste counts)",
        "  --spi-check         compare to sequential map/filter (default on)",
        "  --no-spi-check      skip that compare",
        "  --output-dir PATH   DISTRIBUTED_OUTPUT_DIR for the script",
        "  --julia PATH        remote Julia (ENV or auto)",
        "  $(KIT_HOSTS_FLAG_HELP)",
        "  --hosts-file PATH   one token per line",
        "  $(KIT_QUIET_FLAG_HELP)",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank(io)
    print_help_lines(
        io,
        "See also: plan, go, drive, setup.",
        "API: ride!(script, \"parent:2\", \"child:host:1\"; spi_check=true).",
    )
    return nothing
end

function parse_ride_args(args::AbstractVector{<:AbstractString})
    cli_session, rest = peel_kit_cli_flags(args)
    hosts = String[]
    host_tokens = String[]
    script_path = nothing
    script_args = String[]
    output_dir = nothing
    julia_exe = nothing
    spi_check = true
    c = CliCursor(collect(String, rest))
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if arg == "--analyze"
            throw(ArgumentError("ride: analysis is plan, not ride --analyze"))
        elseif arg == "--output-dir"
            output_dir = cli_take_value!(c, arg)
        elseif arg == "--julia"
            julia_exe = cli_take_value!(c, arg)
        elseif arg == "--spi-check"
            cli_consume!(c)
            spi_check = true
        elseif arg == "--no-spi-check"
            cli_consume!(c)
            spi_check = false
        elseif arg == "--help" || arg == "-h"
            cli_consume!(c)
            append!(hosts, host_tokens)
            append_kit_host_sources!(hosts, cli_session; keep_counts = true)
            if julia_exe === nothing
                env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
                julia_exe = env_val == "auto" ? nothing : env_val
            elseif julia_exe == "auto"
                julia_exe = nothing
            end
            return _ride_parsed(;
                help = true,
                show_version = cli_session.show_version,
                cli_session = cli_session,
                script_path = script_path,
                script_args = script_args,
                hosts = hosts,
                spi_check = spi_check,
                output_dir = output_dir,
                julia = julia_exe,
            )
        elseif endswith(arg, ".jl")
            script_path = arg
            cli_consume!(c)
            while !cli_at_end(c)
                push!(script_args, cli_current(c)::String)
                cli_consume!(c)
            end
            break
        elseif !startswith(arg, "-")
            push!(host_tokens, arg)
            cli_consume!(c)
        else
            throw(ArgumentError("unknown ride option: $arg"))
        end
    end
    append!(hosts, host_tokens)
    append_kit_host_sources!(hosts, cli_session; keep_counts = true)
    for h in hosts
        parse_placement_token(h)
    end
    if julia_exe === nothing
        env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
        julia_exe = env_val == "auto" ? nothing : env_val
    elseif julia_exe == "auto"
        julia_exe = nothing
    end
    apply_kit_cli_session!(cli_session)
    if script_path !== nothing
        require_counted_placement_tokens(hosts; surface = :cli)
    end
    return _ride_parsed(;
        help = false,
        show_version = cli_session.show_version,
        cli_session = cli_session,
        script_path = script_path,
        script_args = script_args,
        hosts = hosts,
        spi_check = spi_check,
        output_dir = output_dir,
        julia = julia_exe,
    )
end
