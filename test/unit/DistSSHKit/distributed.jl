using Test

@testset "distributed" begin
    _with_tempdir() do tmp
        repo = tmp
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

    _with_tempdir() do tmp
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

    @testset "resolve_drive_output_dir" begin
        _with_tempdir() do tmp
            script_dir = joinpath(tmp, "app")
            mkpath(script_dir)
            withenv("DISTRIBUTED_OUTPUT_DIR" => nothing) do
                got = DistSSHKit.resolve_drive_output_dir(script_dir)
                @test got == DistSSHKit.kit_dir_beside_script(script_dir, :drive)
            end
            explicit = joinpath(tmp, "explicit-out")
            withenv("DISTRIBUTED_OUTPUT_DIR" => explicit) do
                got = DistSSHKit.resolve_drive_output_dir(script_dir)
                @test got == DistSSHKit.canonical_local_path(explicit)
            end
        end
    end

    @testset "resolve_drive_log_dir" begin
        _with_tempdir() do tmp
            script_dir = joinpath(tmp, "app")
            mkpath(script_dir)
            withenv("DISTRIBUTED_OUTPUT_DIR" => nothing) do
                @test DistSSHKit.resolve_drive_log_dir(nothing, script_dir) ==
                    DistSSHKit.kit_dir_beside_script(script_dir, :drive)
            end
            env_dir = joinpath(tmp, "env-out")
            withenv("DISTRIBUTED_OUTPUT_DIR" => env_dir) do
                @test DistSSHKit.resolve_drive_log_dir(nothing, script_dir) == env_dir
                explicit = joinpath(tmp, "explicit-logs")
                @test DistSSHKit.resolve_drive_log_dir(explicit, script_dir) == explicit
            end
        end
    end
end
