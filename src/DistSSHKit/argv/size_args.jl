"""Pull `masterhost` / deprecated `local` out of the size host list into `include_local`."""
function _size_absorb_parent_hosts!(hosts::Vector{String}, include_local::Bool)::Bool
    kept = String[]
    inc = include_local
    for h in hosts
        if is_local_host_name(h)
            is_deprecated_local_host_name(h) && warn_deprecated_local_host!()
            inc = true
        else
            push!(kept, h)
        end
    end
    empty!(hosts)
    append!(hosts, kept)
    return inc
end

function show_size_usage(; io::IO=stdout)
    print_help_chrome("DistSSHKit size"; io=io)
    print_help_lines(io,
        "Estimate worker counts from RAM and CPU.",
        "RSS = max(package load, optional --probe peak).",
    )
    print_help_blank(io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit size [masterhost] [hosts...]",
        "  size masterhost host1 host2",
        "  size --gb-per-worker 1.5 host1",
    )
    print_help_blank(io)
    print_help_section("Options"; io=io)
    print_help_lines(io,
        "  -l, --local         deprecated; use the masterhost token (removed in 0.4)",
        "  --gb-per-worker N   skip measure; assume N GB each",
        "  --probe PATH        warm-up script; peak RSS",
        "  --mem-headroom N    RAM fraction (default $(DEFAULT_MEM_HEADROOM))",
        "  --master-gb N       master reserve (default $(DEFAULT_MASTER_GB))",
        "  --hosts CSV         comma-separated hosts (`:N` stripped)",
        "  --hosts-file PATH   one host per line (`:N` stripped)",
        "  $(KIT_QUIET_FLAG_HELP)",
        "  $(KIT_PROGRESS_FLAG_HELP)",
        "  $(KIT_VERBOSE_FLAG_HELP)",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank(io)
    print_help_section("Environment"; io=io)
    print_help_lines(io,
        "  $(KIT_JOBS_ENV_HELP)",
    )
    print_help_blank(io)
    print_help_lines(io,
        "Details: docs (manual/size). See also: drive, setup.",
    )
    return nothing
end

function parse_size_args(args::Vector{String})
    cli_session, args = peel_kit_cli_flags(args)
    gb_per_worker = nothing
    probe         = nothing
    mem_headroom  = DEFAULT_MEM_HEADROOM
    master_gb     = DEFAULT_MASTER_GB
    include_local = false
    hosts         = String[]

    c = CliCursor(args)
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if cli_match(c, ["-h", "--help"])
            cli_consume!(c)
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
        elseif cli_match(c, ["--local", "-l"])
            warn_deprecated_local_host!()
            include_local = true
            cli_consume!(c)
        elseif arg == "--masterhost"
            throw(ArgumentError(
                "size: pass the host token `masterhost` (e.g. size masterhost host1), not `--masterhost`.",
            ))
        elseif arg == "--gb-per-worker"
            gb_per_worker = parse(Float64, cli_take_value!(c, arg))
        elseif arg == "--probe"
            probe = String(cli_take_value!(c, arg))
        elseif arg == "--mem-headroom"
            mem_headroom = parse(Float64, cli_take_value!(c, arg))
        elseif arg == "--master-gb"
            master_gb = parse(Float64, cli_take_value!(c, arg))
        elseif !startswith(arg, "-")
            push!(hosts, split_worker_token(arg)[1])
            cli_consume!(c)
        else
            @warn "Unknown option: $arg (ignored)"
            cli_consume!(c)
        end
    end

    append_kit_host_sources!(hosts, cli_session; keep_counts=false)
    include_local = _size_absorb_parent_hosts!(hosts, include_local)
    apply_kit_cli_session!(cli_session)

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
