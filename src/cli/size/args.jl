function show_size_usage()
    print_help_chrome("DistSSHKit size")
    print_help_lines(
        "Estimate worker counts from RAM and CPU.",
        "RSS = max(package load, optional --probe peak).",
    )
    print_help_blank()
    print_help_section("Usage")
    print_help_lines(
        "  julia --project=. -m DistSSHKit size [--local] [hosts...]",
        "  size --local host1 host2",
        "  size --gb-per-worker 1.5 host1",
    )
    print_help_blank()
    print_help_section("Options")
    print_help_lines(
        "  -l, --local         include localhost",
        "  --gb-per-worker N   skip measure; assume N GB each",
        "  --probe PATH        warm-up script; peak RSS",
        "  --mem-headroom N    RAM fraction (default $(DistSSHKit.DEFAULT_MEM_HEADROOM))",
        "  --master-gb N       master reserve (default $(DistSSHKit.DEFAULT_MASTER_GB))",
        "  --hosts-file PATH   one host per line (`:N` stripped)",
        "  $(DistSSHKit.KIT_QUIET_FLAG_HELP)",
        "  $(DistSSHKit.KIT_PROGRESS_FLAG_HELP)",
        "  $(DistSSHKit.KIT_VERBOSE_FLAG_HELP)",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank()
    print_help_lines(
        "Details: docs (manual/size). See also: drive, setup.",
    )
    return nothing
end

function parse_size_args(args::Vector{String})
    cli_session, args = DistSSHKit.peel_kit_cli_flags(args)
    gb_per_worker = nothing
    probe         = nothing
    mem_headroom  = DistSSHKit.DEFAULT_MEM_HEADROOM
    master_gb     = DistSSHKit.DEFAULT_MASTER_GB
    include_local = false
    hosts         = String[]

    c = DistSSHKit.CliCursor(args)
    while !DistSSHKit.cli_at_end(c)
        arg = DistSSHKit.cli_current(c)::String
        if DistSSHKit.cli_match(c, ["-h", "--help"])
            DistSSHKit.cli_consume!(c)
            return (
                show_help=true,
                show_version=cli_session.show_version,
                cli_session=cli_session,
                gb_per_worker=gb_per_worker,
                probe=probe,
                mem_headroom=mem_headroom,
                master_gb=master_gb,
                include_local=include_local,
                hosts=hosts,
            )
        elseif DistSSHKit.cli_match(c, ["--local", "-l"])
            include_local = true
            DistSSHKit.cli_consume!(c)
        elseif arg == "--gb-per-worker"
            gb_per_worker = parse(Float64, DistSSHKit.cli_take_value!(c, arg))
        elseif arg == "--probe"
            probe = String(DistSSHKit.cli_take_value!(c, arg))
        elseif arg == "--mem-headroom"
            mem_headroom = parse(Float64, DistSSHKit.cli_take_value!(c, arg))
        elseif arg == "--master-gb"
            master_gb = parse(Float64, DistSSHKit.cli_take_value!(c, arg))
        elseif !startswith(arg, "-")
            push!(hosts, DistSSHKit.split_host_workers_spec(arg)[1])
            DistSSHKit.cli_consume!(c)
        else
            @warn "Unknown option: $arg (ignored)"
            DistSSHKit.cli_consume!(c)
        end
    end

    DistSSHKit.append_hosts_file!(hosts, cli_session)
    DistSSHKit.apply_kit_cli_session!(cli_session)

    if probe === nothing
        env_probe = strip(get(ENV, "DISTSSHKIT_SIZE_PROBE", ""))
        !isempty(env_probe) && (probe = String(env_probe))
    end

    return (
        show_help=false,
        show_version=cli_session.show_version,
        cli_session=cli_session,
        gb_per_worker=gb_per_worker,
        probe=probe,
        mem_headroom=mem_headroom,
        master_gb=master_gb,
        include_local=include_local,
        hosts=hosts,
    )
end
