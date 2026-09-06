#!/usr/bin/env julia
"""
`julia -m DistSSHKit ride` — experimental auto-split of map / filter / comprehensions.

  julia --project=. -m DistSSHKit ride SCRIPT.jl
  julia --project=. -m DistSSHKit ride parent:2 SCRIPT.jl
  julia --project=. -m DistSSHKit ride parent:1 child:host1:2 SCRIPT.jl

See `--help`. Analysis is `plan`, not this command.
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
include(joinpath(@__DIR__, "ride", "_using.jl"))

const PROJECT_ROOT = cli_project_root(@__DIR__)

function ride_main()::Cint
    parsed = parse_ride_args(ARGS)
    if parsed.show_version
        println_kit_version()
        return 0
    end
    if parsed.help
        show_ride_usage()
        return 0
    end
    if parsed.script_path === nothing
        show_ride_usage()
        return 0
    end
    tok = parsed.hosts
    sess = nothing
    if !isempty(tok)
        pt = parse_worker_tokens(tok)
        if !worker_tokens_fully_specified(pt)
            sess = KitSession(;
                project=PROJECT_ROOT,
                workers=tok,
                include_parent_for_size=pt.parent_autosize,
            )
        end
    end
    result = ride!(
        parsed.script_path,
        tok;
        args=parsed.script_args,
        spi_check=parsed.spi_check,
        output_dir=parsed.output_dir,
        project=PROJECT_ROOT,
        julia=parsed.julia,
        session=sess,
        gb_per_worker=parsed.gb_per_worker,
        probe=parsed.probe,
        mem_headroom=parsed.mem_headroom,
        parent_gb=parsed.parent_gb,
    )
    if !(kit_output_progress() && result.ok)
        print_ride(result)
    end
    return result.ok ? 0 : 1
end

if get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", "") != "1" &&
   !isempty(PROGRAM_FILE) &&
   abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(ride_main())
end
