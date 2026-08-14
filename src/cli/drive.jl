#!/usr/bin/env julia
"""
`julia -m DistSSHKit drive` — run a driver on local/SSH workers, then collect remote outputs.

  julia --project=. -m DistSSHKit drive
  julia --project=. -m DistSSHKit drive l:9 host1:10 script.jl
  julia --project=. -m DistSSHKit drive --collect-missing data/out host1 host2

See `--help`.
"""

# Prefer package DistSSHKit; fall back to vendored include.
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
include(joinpath(@__DIR__, "drive", "_using.jl"))

const PROJECT_ROOT = cli_project_root(@__DIR__)
const _PATH_ANCHOR = DistSSHKit.canonical_local_path(PROJECT_ROOT)

# Execution core lives under DistSSHKit/drive/runtime/ (Main-scoped for Distributed).
include(joinpath(@__DIR__, "..", "DistSSHKit", "drive", "_load_runtime.jl"))

function _restore_drive_args!(original_args::Vector{String})
    empty!(ARGS)
    append!(ARGS, original_args)
end

function drive_main()::Cint
    original_args = copy(ARGS)
    try
        return _drive_main_body(original_args)
    finally
        _restore_drive_args!(original_args)
    end
end

function _drive_main_body(original_args::Vector{String})::Cint
    parsed = parse_drive_args(ARGS)
    return run_drive_parsed!(parsed; original_args=original_args)
end

if get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", "") != "1" &&
   !isempty(PROGRAM_FILE) &&
   abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(drive_main())
end
