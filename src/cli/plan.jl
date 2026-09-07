#!/usr/bin/env julia
"""
`julia -m DistSSHKit plan` — inspect a script; do not start a job.

  julia --project=. -m DistSSHKit plan SCRIPT.jl

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
include(joinpath(@__DIR__, "plan", "_using.jl"))

const PROJECT_ROOT = cli_project_root(@__DIR__)

function plan_main()::Cint
    opts = parse_plan_args(ARGS)
    if opts.show_help
        show_plan_usage()
        return 0
    end
    if opts.show_version
        DistSSHKit.println_kit_version()
        return 0
    end
    if opts.script_path === nothing
        show_plan_usage()
        return 0
    end
    kp = plan(
        opts.script_path;
        workers = opts.tokens,
        project = PROJECT_ROOT,
        gb_per_worker = opts.gb_per_worker,
        probe = opts.probe,
        mem_headroom = opts.mem_headroom,
        parent_gb = opts.parent_gb,
    )
    print_plan(kp)
    return kp.ok ? 0 : 1
end

if get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", "") != "1" &&
        !isempty(PROGRAM_FILE) &&
        abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(plan_main())
end
