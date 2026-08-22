using Test

# Oracle: dispatcher only (plus detached `:go`, which is out-of-process).
# `execute!(:drive, …)` includes a driver into `Main` and lives in
# `integration/drive/execute.jl` (after `api.jl`, which is the first
# in-process `drive!` and owns the warn-overwrite check).

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

    @testset "detached rejects unknown / yes=false" begin
        err = try
            DistSSHKit.execute!(:go, "job.jl", ["local:1"]; detached=true, plan=nothing)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("does not accept keyword :plan", sprint(showerror, err))

        err2 = try
            DistSSHKit.execute!(:go, "job.jl", ["local:1"]; detached=true, yes=false)
            nothing
        catch e
            e
        end
        @test err2 isa ArgumentError
        @test occursin("yes=true", sprint(showerror, err2))

        err3 = try
            DistSSHKit.execute!(:go, "job.jl", ["local:1"]; detached=true, log_dir="x")
            nothing
        catch e
            e
        end
        @test err3 isa ArgumentError
        @test occursin(":log_dir", sprint(showerror, err3))
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
            @test read(joinpath(result.output_dir, "parenthost", "args.txt"), String) == "8"
        end
    end

    @testset ":go detached" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"ExecuteGoDetached\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                write(joinpath(out, "args.txt"), join(ARGS, ","))
                """)
            mktemp() do _, out_io
                mktemp() do _, err_io
                    kp = DistSSHKit.execute!(
                        :go,
                        script,
                        ["local:1"];
                        detached=true,
                        project=proj,
                        args=["8"],
                        quiet=true,
                        stdout=out_io,
                        stderr=err_io,
                    )
                    result = wait(kp)
                    flush(out_io)
                    flush(err_io)
                    @test kp isa DistSSHKit.KitProcess
                    @test kp.kind === :go
                    @test kp.log_dir === nothing
                    @test kp.output_dir !== nothing
                    @test result isa DistSSHKit.KitRunResult
                    @test result.kind === :go
                    @test result.ok
                    @test result.exit_code == 0
                    @test result.output_dir == kp.output_dir
                    @test result.log_dir === nothing
                    @test read(joinpath(result.output_dir, "parenthost", "args.txt"), String) == "8"
                end
            end
        end
    end
end
