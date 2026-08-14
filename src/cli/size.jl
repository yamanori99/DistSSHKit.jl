#!/usr/bin/env julia
"""
`julia -m DistSSHKit size` — estimate worker counts from RAM/CPU.

  julia --project=. -m DistSSHKit size --local host1 host2
  julia --project=. -m DistSSHKit size --gb-per-worker 1.5 host1

See `--help`.
"""

if !isdefined(@__MODULE__, :DistSSHKit)
    if get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", "") == "1"
        import DistSSHKit
    else
        try
            import DistSSHKit
        catch
            include(joinpath(@__DIR__, "..", "DistSSHKit.jl"))
        end
    end
end
include(joinpath(@__DIR__, "size", "_using.jl"))

const PROJECT_ROOT = cli_project_root(@__DIR__)
const _PATH_ANCHOR = DistSSHKit.canonical_local_path(PROJECT_ROOT)

function size_main()::Cint
    opts = parse_size_args(ARGS)
    if opts.show_help
        show_size_usage()
        return 0
    end
    if opts.show_version
        DistSSHKit.println_kit_version()
        return 0
    end
    hosts = opts.hosts
    all_hosts = opts.include_local ? ["localhost"; hosts] : hosts

    if isempty(all_hosts)
        show_size_usage()
        return 0
    end

    print_header("DistSSHKit size")
    DistSSHKit.writeln_field("Project", cli_project_disp(PROJECT_ROOT, _PATH_ANCHOR))
    DistSSHKit.kit_println()

    samples = resolve_worker_memory_samples(PROJECT_ROOT, all_hosts, hosts, opts)
    samples === nothing && return 1
    DistSSHKit.kit_println()

    print_size_report(
        all_hosts, hosts, samples, opts;
        show_peak=(opts.probe !== nothing && opts.gb_per_worker === nothing),
    )
    return 0
end

if get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", "") != "1" &&
   !isempty(PROGRAM_FILE) &&
   abspath(PROGRAM_FILE) == abspath(@__FILE__)
    size_main()
end
