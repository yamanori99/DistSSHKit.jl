using Test

@testset "distributed" begin
    mktempdir() do tmp
        repo = abspath(string(tmp))
        sd = joinpath(repo, "scripts")
        mkpath(sd)
        out2 = joinpath(repo, "nested", "out2")
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "out1:$(out2)",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "ignored"),
        ) do
            roots = DistSSHKit.distributed_collect_root_dirs(sd, repo)
            @test roots == String[abspath(joinpath(repo, "out1")), abspath(out2)]
        end
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "out1:out1",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "ignored"),
        ) do
            roots = DistSSHKit.distributed_collect_root_dirs(sd, repo)
            @test roots == String[abspath(joinpath(repo, "out1"))]
        end
        withenv(
            "DISTRIBUTED_COLLECT_DIRS" => "",
            "DISTRIBUTED_OUTPUT_DIR" => joinpath(repo, "solo"),
        ) do
            @test DistSSHKit.distributed_collect_root_dirs(sd, repo) ==
                String[abspath(joinpath(repo, "solo"))]
        end
    end

    mktempdir() do tmp
        default = joinpath(tmp, "output")
        withenv("DISTRIBUTED_OUTPUT_DIR" => nothing) do
            @test DistSSHKit.resolve_distributed_output_dir!(String[], default) == abspath(default)
            @test ENV["DISTRIBUTED_OUTPUT_DIR"] == abspath(default)
        end

        custom = joinpath(tmp, "custom")
        withenv("DISTRIBUTED_OUTPUT_DIR" => custom) do
            @test DistSSHKit.resolve_distributed_output_dir!(String[], default) == abspath(custom)
        end

        from_args = joinpath(tmp, "from_args")
        withenv("DISTRIBUTED_OUTPUT_DIR" => "") do
            got = DistSSHKit.resolve_distributed_output_dir!(
                String["--output-dir", from_args],
                default,
            )
            @test got == abspath(from_args)
        end
    end
end
