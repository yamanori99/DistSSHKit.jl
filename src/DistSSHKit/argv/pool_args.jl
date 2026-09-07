# Argument parsing for `pool` (inventory + health; no RSS probe).

function _pool_parsed(;
        show_help::Bool,
        show_version::Bool,
        cli_session,
        gb_per_worker,
        mem_headroom::Float64,
        parent_gb::Float64,
        include_parent::Bool,
        hosts::Vector{String},
    )
    return (
        show_help = show_help,
        show_version = show_version,
        cli_session = cli_session,
        gb_per_worker = gb_per_worker,
        mem_headroom = mem_headroom,
        parent_gb = parent_gb,
        include_parent = include_parent,
        hosts = hosts,
    )
end

function show_pool_usage(; io::IO = stdout)
    print_help_chrome("DistSSHKit pool"; io = io)
    print_help_lines(
        io,
        "Show cluster cores, RAM, and a slot hint. Does not start a job.",
        "Fail-closed: unreachable listed hosts make the command fail.",
        "RSS measurement stays on size / size!.",
    )
    print_help_blank(io)
    print_help_section("Usage"; io = io)
    print_help_lines(
        io,
        "  julia --project=. -m DistSSHKit pool [parent] [child:NAME...]",
        "  pool parent child:host1 child:host2",
        "  pool --gb-per-worker 1.5 child:host1",
    )
    print_help_blank(io)
    print_help_section("Options"; io = io)
    print_help_lines(
        io,
        "  --gb-per-worker N   slot hint; default $(WORKER_MEMORY_GB_FALLBACK) GB (no RSS)",
        "  --mem-headroom N    RAM fraction (default $(DEFAULT_MEM_HEADROOM))",
        "  --parent-gb N       parent process reserve (default $(DEFAULT_PARENT_GB))",
        "  --hosts CSV         parent / child:NAME[:N] (`:N` stripped)",
        "  --hosts-file PATH   same, one token per line",
        "  $(KIT_QUIET_FLAG_HELP)",
        "  $(KIT_PROGRESS_FLAG_HELP)",
        "  $(KIT_VERBOSE_FLAG_HELP)",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank(io)
    print_help_lines(
        io,
        "Details: docs (manual/pool). See also: size, setup.",
        "API: pool!(session) -> ResourcePool.",
    )
    return nothing
end

function parse_pool_args(args::Vector{String})
    cli_session, args = peel_kit_cli_flags(args)
    gb_per_worker = nothing
    mem_headroom = DEFAULT_MEM_HEADROOM
    parent_gb = DEFAULT_PARENT_GB
    include_parent = false
    hosts = String[]

    c = CliCursor(args)
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if cli_match(c, ["-h", "--help"])
            cli_consume!(c)
            return _pool_parsed(;
                show_help = true,
                show_version = cli_session.show_version,
                cli_session = cli_session,
                gb_per_worker = gb_per_worker,
                mem_headroom = mem_headroom,
                parent_gb = parent_gb,
                include_parent = include_parent,
                hosts = hosts,
            )
        elseif cli_match(c, ["--local", "-l"]) || startswith(arg, "--local:") || startswith(arg, "-l:")
            throw_removed_local_flag(arg)
        elseif arg == "--parenthost" || arg == "--masterhost" || arg == "--parent"
            throw(
                ArgumentError(
                    "pool: pass the token `parent` (e.g. pool parent child:host1), not `--parenthost`.",
                )
            )
        elseif arg == "--gb-per-worker"
            gb_per_worker = parse(Float64, cli_take_value!(c, arg))
        elseif arg == "--probe"
            throw(ArgumentError("pool: RSS probe is size --probe, not pool"))
        elseif arg == "--mem-headroom"
            mem_headroom = parse(Float64, cli_take_value!(c, arg))
        elseif arg == "--master-gb"
            throw(ArgumentError("pool: use `--parent-gb N`, not `--master-gb`"))
        elseif arg == "--parent-gb"
            parent_gb = parse(Float64, cli_take_value!(c, arg))
        elseif !startswith(arg, "-")
            let p = parse_placement_token(arg)
                push!(hosts, p.role === :parent ? PARENT_HOST_NAME : p.name)
            end
            cli_consume!(c)
        else
            @warn "Unknown option: $arg (ignored)"
            cli_consume!(c)
        end
    end

    append_kit_host_sources!(hosts, cli_session; keep_counts = false, roles = true)
    include_parent = _size_absorb_parent_hosts!(hosts, include_parent)
    apply_kit_cli_session!(cli_session)

    return _pool_parsed(;
        show_help = false,
        show_version = cli_session.show_version,
        cli_session = cli_session,
        gb_per_worker = gb_per_worker,
        mem_headroom = mem_headroom,
        parent_gb = parent_gb,
        include_parent = include_parent,
        hosts = hosts,
    )
end
