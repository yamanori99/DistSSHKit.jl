using Test

# Subprocess wiring for `julia -m DistSSHKit setup` (1 sad + 1 happy per mode).
# Module-level validate / op outcomes live under DistSSHKit/setup/.

@testset "setup CLI exit codes" begin
    @testset "host validation wiring" begin
        proc, combined = _run_kit_setup(setup_args=["--delete", "local"])
        @test proc.exitcode == 1
        @test occursin("SSH targets only", combined)
    end

    @testset "delete" begin
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--delete", "host1"],
                extra_env=merge(
                    _fake_setup_remote_env(state_dir),
                    Dict("DISTSSHKIT_TEST_SSH_FAIL" => "1"),
                ),
            )
            @test proc.exitcode == 1
            @test occursin("SSH preflight failed", combined)
        end
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--delete", "host1", "host2"],
                extra_env=_fake_setup_remote_env(state_dir),
            )
            @test proc.exitcode == 0
            @test occursin("Delete complete (2 host(s))", combined)
        end
    end

    @testset "rsync" begin
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--rsync", "host1"],
                extra_env=merge(
                    _fake_setup_remote_env(state_dir),
                    Dict("DISTSSHKIT_TEST_MKDIR_FAIL" => "1"),
                ),
            )
            @test proc.exitcode == 1
            @test occursin("rsync did not succeed on any host", combined)
        end
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--rsync", "host1", "host2"],
                extra_env=_fake_setup_remote_env(state_dir),
            )
            @test proc.exitcode == 0
            @test occursin("rsync complete (2 host(s))", combined)
        end
    end
end
