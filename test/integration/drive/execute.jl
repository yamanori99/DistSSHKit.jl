using Test

# Oracle: `execute!(:drive, …)` is `drive!` plus `kit_run_result`. In-process
# (same as `api.jl`). Must run *after* `api.jl`: that file is the first
# `include` of a driver into `Main` and owns the warn-overwrite check.
# Stderr is captured: this file's second `main` include warns, and
# `rmprocs` prints worker teardown (`Worker N terminated` / Unhandled Task).
# Detached inherits stdio; capture spawn+`wait` the same way.

@testset "execute! :drive" begin
    fixture = _fixture("drive_local_smoke.jl")
    _mktemp_host() do proj
        _write_host_project!(proj, "ExecuteDrive")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        prev_v = DistSSHKit.kit_verbosity()
        try
            mktemp() do out_path, out_io
                mktemp() do _, err_io
                    result = redirect_stdout(out_io) do
                        redirect_stderr(err_io) do
                            DistSSHKit.execute!(
                                :drive,
                                script,
                                ["parenthost:2"];
                                project=proj,
                                verbosity=:verbose,
                                yes=true,
                            )
                        end
                    end
                    flush(out_io)
                    flush(err_io)
                    out = read(out_path, String)
                    @test result isa DistSSHKit.KitRunResult
                    @test result.kind === :drive
                    @test result.ok
                    @test result.exit_code == 0
                    @test result.output_dir !== nothing
                    @test result.log_dir !== nothing
                    let od = result.output_dir
                        od === nothing && error("expected execute! output_dir")
                        _assert_kit_progress_done(od; kind=:drive)
                    end
                    @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", out)
                    # stderr: second `main` include after `api.jl` (warn-overwrite)
                    # plus Distributed worker teardown. Captured, not asserted.
                end
            end
        finally
            DistSSHKit.set_kit_verbosity!(prev_v)
        end
    end
end

@testset "execute! :drive detached" begin
    fixture = _fixture("drive_local_smoke.jl")
    _mktemp_host() do proj
        _write_host_project!(proj, "ExecuteDriveDetached")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        mktemp() do out_path, out_io
            mktemp() do _, err_io
                kp = DistSSHKit.execute!(
                    :drive,
                    script,
                    ["parenthost:2"];
                    detached=true,
                    project=proj,
                    verbosity=:verbose,
                    mem_headroom=0.5,
                    master_gb=0.2,
                    stdout=out_io,
                    stderr=err_io,
                )
                result = wait(kp)
                flush(out_io)
                flush(err_io)
                out = read(out_path, String)
                @test kp isa DistSSHKit.KitProcess
                @test kp.kind === :drive
                @test kp.output_dir !== nothing
                @test kp.log_dir !== nothing
                @test result isa DistSSHKit.KitRunResult
                @test result.kind === :drive
                @test result.ok
                @test result.exit_code == 0
                @test result.output_dir == kp.output_dir
                @test result.log_dir == kp.log_dir
                @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", out)
                @test !isfile(joinpath(result.output_dir, "kit.pid"))
                @test !isfile(joinpath(result.log_dir, "kit.pid"))
                recovered = DistSSHKit.kit_result_from_dir(result.output_dir)
                @test recovered isa DistSSHKit.KitRunResult
                @test recovered.ok
                @test recovered.kind === :drive
                @test recovered.exit_code == 0
            end
        end
    end
end
