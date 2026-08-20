using Test

# Oracle: `execute!(:drive, …)` is `drive!` plus `kit_run_result`. In-process
# (same as `api.jl`). Must run *after* `api.jl`: that file is the first
# `include` of a driver into `Main` and owns the warn-overwrite check.

@testset "execute! :drive" begin
    fixture = _fixture("drive_local_smoke.jl")
    _mktemp_host() do proj
        _write_host_project!(proj, "ExecuteDrive")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        prev_v = DistSSHKit.kit_verbosity()
        try
            mktemp() do out_path, out_io
                result = redirect_stdout(out_io) do
                    DistSSHKit.execute!(
                        :drive,
                        script,
                        ["local:2"];
                        project=proj,
                        verbosity=:verbose,
                        yes=true,
                    )
                end
                flush(out_io)
                out = read(out_path, String)
                @test result isa DistSSHKit.KitRunResult
                @test result.kind === :drive
                @test result.ok
                @test result.exit_code == 0
                @test result.output_dir !== nothing
                @test result.log_dir !== nothing
                @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", out)
            end
        finally
            DistSSHKit.set_kit_verbosity!(prev_v)
        end
    end
end
