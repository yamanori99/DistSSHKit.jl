using Test

# Oracle: `drive!(…, "parenthost:2")` runs the smoke driver in this process.
# CLI child is `local.jl`. Not SSH.
#
# First in-process `include` of a driver into `Main`. Later files (e.g.
# `integration/drive/execute.jl`) share that `Main` and will warn-overwrite
# `main()`. Keep this file before those includes in `runtests.jl`.

@testset "drive! l:N" begin
    fixture = _fixture("drive_local_smoke.jl")
    _mktemp_host() do proj
        _write_host_project!(proj, "DriveApiSmoke")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        # `:quiet` sends driver stdout to the kit log only. Use `:verbose` so
        # SMOKE_OK is on the captured stream (same string as CLI `local.jl`).
        prev_v = DistSSHKit.kit_verbosity()
        try
            mktemp() do out_path, out_io
                mktemp() do err_path, err_io
                    result = redirect_stdout(out_io) do
                        redirect_stderr(err_io) do
                            DistSSHKit.drive!(
                                script,
                                "parenthost:2";
                                project=proj,
                                verbosity=:verbose,
                                yes=true,
                            )
                        end
                    end
                    flush(out_io)
                    flush(err_io)
                    out = read(out_path, String)
                    err = read(err_path, String)
                    @test result.ok
                    @test result.exit_code == 0
                    @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", out)
                    # No explicit output_dir=/log_dir= — still resolved (not the raw `nothing` kwarg).
                    @test result.output_dir !== nothing
                    @test result.log_dir !== nothing
                    # `@everywhere` must not redefine master helpers (warn-overwrite).
                    @test !occursin("overwritten", err)
                end
            end
        finally
            DistSSHKit.set_kit_verbosity!(prev_v)
        end
    end
end
