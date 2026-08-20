using Test

# Oracle: dispatcher only. `execute!(:drive, …)` includes a driver into `Main`
# and lives in `integration/drive/execute.jl` (after `api.jl`, which is the
# first in-process `drive!` and owns the warn-overwrite check).

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
end
