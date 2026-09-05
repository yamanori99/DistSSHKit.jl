using Test

# Oracle: kit `setup` CLI in a child julia — exit code and a message needle
# (1 sad + 1 happy per mode). Fake ssh/rsync only; not real OpenSSH.
# Module-level validate / op outcomes live under unit/DistSSHKit/setup/.

@testset "setup CLI exit codes" begin
    @testset "host validation wiring" begin
        proc, combined = _run_kit_setup(setup_args=["--delete", "parent"])
        @test proc.exitcode == 1
        @test occursin("only for --juliaup", combined)
        proc2, combined2 = _run_kit_setup(setup_args=["--delete", "host1"])
        @test proc2.exitcode == 1
        @test occursin("child:NAME", combined2) || occursin("parent[:N]", combined2)
    end

    @testset "delete" begin
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--delete", "child:host1"],
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
                setup_args=["--delete", "child:host1", "child:host2"],
                extra_env=_fake_setup_remote_env(state_dir),
            )
            @test proc.exitcode == 0
            @test occursin("Delete complete (2 host(s))", combined)
        end
    end

    @testset "rsync" begin
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--rsync", "child:host1"],
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
                setup_args=["--rsync", "child:host1", "child:host2"],
                extra_env=_fake_setup_remote_env(state_dir),
            )
            @test proc.exitcode == 0
            @test occursin("rsync complete (2 host(s))", combined)
        end
    end

    @testset "runtest" begin
        # `--julia` skips remote detect; fake ssh still sees `Pkg.test()`.
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--runtest", "--julia", "/bin/echo", "child:host1"],
                extra_env=merge(
                    _fake_setup_remote_env(state_dir),
                    Dict("DISTSSHKIT_TEST_PKG_TEST_FAIL" => "1"),
                ),
            )
            @test proc.exitcode == 1
            @test occursin("Pkg.test did not succeed on any host", combined)
        end
        _with_tempdir() do state_dir
            proc, combined = _run_kit_setup(
                setup_args=["--runtest", "--julia", "/bin/echo", "child:host1", "child:host2"],
                extra_env=_fake_setup_remote_env(state_dir),
            )
            @test proc.exitcode == 0
            @test occursin("Pkg.test complete (2 host(s))", combined)
        end
    end
end
