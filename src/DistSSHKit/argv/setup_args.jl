function show_requirements(; io::IO=stdout)
    print_help_chrome("DistSSHKit setup"; io=io)
    print_help_lines(io,
        "Deploy and check the project on SSH hosts before go / drive.",
        "Recommended: --rsync, --instantiate, --check, then optional --runtest.",
        "Remote path: ~/Parent/RepoName, or --remote-path / ENV.",
        "Git parity is drive --require-git (off by default).",
    )
    print_help_blank(io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit setup MODE host1 host2",
        "  setup --rsync host1 host2",
        "  setup --instantiate host1 host2",
        "  setup --check host1 host2",
        "  setup --runtest host1 host2",
    )
    print_help_blank(io)
    print_help_section("Modes (one per run)"; io=io)
    print_help_lines(io,
        "  --rsync / --clone    empty remote path only",
        "                       --delete first to replace",
        "  --sync / --pull      git update (confirm unless -y)",
        "  --instantiate        Pkg.instantiate on remotes",
        "  --check              SSH, Julia, project, deps",
        "  --runtest            Pkg.test of the job project on remotes",
        "  --cleanup / --delete stale workers / remote tree",
        "                       cleanup: $(KIT_SKIP_PKILL_ENV_HELP)",
    )
    print_help_blank(io)
    print_help_section("Options"; io=io)
    print_help_lines(io,
        "  --repo URL           clone URL (default: origin)",
        "  --remote-path PATH   remote project root",
        "  --julia PATH         remote Julia",
        "  $(KIT_QUIET_FLAG_HELP)",
        "  $(KIT_PROGRESS_FLAG_HELP)",
        "  $(KIT_VERBOSE_FLAG_HELP)",
        "  -y, --yes            skip confirmations",
        "  --hosts CSV         comma-separated hosts (`:N` stripped)",
        "  --hosts-file PATH    one host per line (`:N` stripped)",
        "  --version, -v        print version and exit",
        "  -h, --help           this help",
    )
    print_help_blank(io)
    print_help_section("Environment"; io=io)
    print_help_lines(io,
        "  $(KIT_JOBS_ENV_HELP)",
    )
    print_help_blank(io)
    print_help_lines(io,
        "Details: docs (manual/setup). See also: go, drive, size.",
    )
end

function parse_setup_args(args::Vector{String})
    cli_session, args = peel_kit_cli_flags(args)
    mode = nothing
    julia_path = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")  # default to env or auto-detect
    repo_url = nothing
    remote_path_override = nothing
    hosts = String[]
    show_help = false
    ignore_julia_version = false

    c = CliCursor(args)
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if arg == "--check"
            mode = :check
            cli_consume!(c)
        elseif arg == "--pull"
            mode = :pull
            cli_consume!(c)
        elseif arg == "--sync"
            mode = :sync
            cli_consume!(c)
        elseif arg == "--instantiate"
            mode = :instantiate
            cli_consume!(c)
        elseif arg == "--runtest"
            mode = :runtest
            cli_consume!(c)
        elseif arg == "--cleanup"
            mode = :cleanup
            cli_consume!(c)
        elseif arg == "--clone"
            mode = :clone
            cli_consume!(c)
        elseif arg == "--delete"
            mode = :delete
            cli_consume!(c)
        elseif arg == "--rsync"
            mode = :rsync_push
            cli_consume!(c)
        elseif arg == "--requirements"
            mode = :requirements
            cli_consume!(c)
        elseif arg == "--julia"
            julia_path = cli_take_value!(c, arg)
        elseif arg == "--repo"
            repo_url = String(strip(cli_take_value!(c, arg)))
        elseif arg in ("--remote-path", "--remote-dir")
            remote_path_override = String(strip(cli_take_value!(c, arg)))
        elseif arg == "--ignore-julia-version"
            ignore_julia_version = true
            cli_consume!(c)
        elseif cli_match(c, ["-h", "--help"])
            show_help = true
            cli_consume!(c)
        else
            push!(hosts, split_host_workers_spec(arg)[1])
            cli_consume!(c)
        end
    end

    append_kit_host_sources!(hosts, cli_session; keep_counts=false)
    apply_kit_cli_session!(cli_session)

    return (
        mode=mode,
        julia_path=julia_path,
        repo_url=repo_url,
        remote_path_override=remote_path_override,
        hosts=hosts,
        show_help=show_help,
        ignore_julia_version=ignore_julia_version,
        show_version=cli_session.show_version,
        cli_session=cli_session,
    )
end

show_usage(; io::IO=stdout) = show_requirements(; io)
setup_help_text()::String = sprint(io -> show_requirements(; io))
