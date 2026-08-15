using Test

# Oracle: `drive!(…, "local:2")` runs the smoke driver in this process.
# CLI child is `local.jl`. Not SSH.

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
            mktemp() do path, io
                result = redirect_stdout(io) do
                    DistSSHKit.drive!(
                        script,
                        "local:2";
                        project=proj,
                        verbosity=:verbose,
                        yes=true,
                    )
                end
                flush(io)
                out = read(path, String)
                @test result.ok
                @test result.exit_code == 0
                @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", out)
            end
        finally
            DistSSHKit.set_kit_verbosity!(prev_v)
        end
    end
end
