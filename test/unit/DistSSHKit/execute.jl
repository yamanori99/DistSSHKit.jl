using Test

# Oracle: `execute!` is a thin dispatcher onto `go!` / `drive!`. Coverage here
# is the dispatch itself (bad kind, kind tag, forwarded kwargs) — `go!` /
# `drive!` behavior itself is covered by their own unit/integration tests.

@testset "execute!" begin
    @testset "kind not :go / :drive" begin
        err = try
            DistSSHKit.execute!(:pipeline, "job.jl", String[])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin(":go or :drive", sprint(showerror, err))
    end

    @testset ":go dispatch" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"ExecuteGo\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                write(joinpath(out, "args.txt"), join(ARGS, ","))
                """)
            result = DistSSHKit.execute!(
                :go,
                script,
                ["local:1"];
                project=proj,
                args=["8"],
                quiet=true,
                yes=true,
            )
            @test result isa DistSSHKit.KitRunResult
            @test result.kind === :go
            @test result.ok
            @test result.exit_code == 0
            @test result.output_dir !== nothing
            @test read(joinpath(result.output_dir, "local", "args.txt"), String) == "8"
        end
    end

    @testset ":drive dispatch" begin
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
end
