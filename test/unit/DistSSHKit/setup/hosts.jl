using Test

# Module setup hosts — validate + op return values (CLI exit codes live in integration/setup/exit.jl).

@testset "setup hosts safety" begin
    function _with_fake_remotes(f::Function; extra_env=Dict{String,String}())
        _with_tempdir() do state_dir
            withenv(merge(_fake_setup_remote_env(state_dir), extra_env)...) do
                _apply_quiet_setup_session!()
                return f(state_dir)
            end
        end
    end

    @testset "validate_setup_hosts" begin
        # Representative refusals; DistSSHKit/hosts.jl covers the underlying predicates.
        @test_throws ArgumentError DistSSHKit.validate_setup_hosts(String[])
        @test_throws ArgumentError DistSSHKit.validate_setup_hosts(["parent"])
        @test DistSSHKit.validate_setup_hosts(["parent"]; allow_parent=true) === nothing
        @test DistSSHKit.validate_setup_hosts(["parent", "host-a"]; allow_parent=true) === nothing
        @test DistSSHKit.setup_juliaup_ssh_hosts(["parent", "host-a"]) == ["host-a"]
        @test DistSSHKit.setup_juliaup_ssh_hosts(["parent"]) == String[]
        @test DistSSHKit.validate_setup_hosts(["local"]) === nothing
        @test_throws ArgumentError DistSSHKit.validate_setup_hosts(["demos/foo.jl"])
        @test DistSSHKit.validate_setup_hosts(["root@192.0.2.10", "host-b"]) === nothing
    end

        @testset "finish_host_op!" begin
            _apply_quiet_setup_session!()
            @test DistSSHKit.finish_host_op!(
                "X",
                (; cancelled=true, succeeded=0, failed=0),
            )
            out, ok = _capture_stdio() do _, _
                DistSSHKit.finish_host_op!(
                    "Pkg.test",
                    (; cancelled=false, succeeded=0, failed=2),
                )
            end
            @test !ok
            @test occursin("Pkg.test did not succeed on any host", out)
            out2, ok2 = _capture_stdio() do _, _
                DistSSHKit.finish_host_op!(
                    "Pkg.test",
                    (; cancelled=false, succeeded=1, failed=1),
                )
            end
            @test !ok2
            @test occursin("failed on 1 host", out2)
            _, ok3 = _capture_stdio() do _, _
                DistSSHKit.finish_host_op!(
                    "Pkg.test",
                    (; cancelled=false, succeeded=2, failed=0),
                )
            end
            @test ok3
        end

    @testset "probe / preflight" begin
        _with_fake_remotes() do _
            @test DistSSHKit.probe_setup_ssh("host1") === nothing
            @test DistSSHKit.preflight_setup_ssh(["host1", "host2"])
        end
        _with_fake_remotes(extra_env=Dict("DISTSSHKIT_TEST_SSH_FAIL" => "1")) do _
            @test DistSSHKit.probe_setup_ssh("host1") isa String
            @test DistSSHKit.preflight_setup_ssh(["host1"]) == false
        end
    end

    @testset "delete_remotes" begin
        withenv("DISTSSHKIT_YES" => nothing) do
            prev_ni = DistSSHKit.kit_noninteractive()
            DistSSHKit.set_kit_noninteractive!(false)
            try
                for v in (:quiet, :progress, :verbose)
                    with_kit_verbosity(v) do
                        out, result = _capture_stdio() do stdin_io, _
                            println(stdin_io, "no")
                            flush(stdin_io)
                            seekstart(stdin_io)
                            DistSSHKit.delete_remotes(["host1"], "~/App.jl")
                        end
                        @test result.cancelled && result.succeeded == 0 && result.failed == 0
                        @test isempty(result.hosts)
                        @test occursin("Cancelled.", out)
                        @test occursin("DELETE", out)
                        @test occursin("Type 'delete'", out)
                        @test occursin("~/App.jl", out)
                    end
                end
            finally
                DistSSHKit.set_kit_noninteractive!(prev_ni)
            end
        end

        _with_fake_remotes() do state_dir
            host = "host1"
            slot = replace(host, r"[@:/]" => "_")
            tree = joinpath(state_dir, slot, "tree")
            mkpath(tree)
            touch(joinpath(tree, "keepme.txt"))
            result = DistSSHKit.delete_remotes([host], "~/App.jl"; confirm=false)
            @test !result.cancelled && result.succeeded == 1 && result.failed == 0
            @test length(result.hosts) == 1 && result.hosts[1].ok
            @test !isdir(joinpath(state_dir, slot))
        end
    end

    @testset "clone_to_remotes" begin
        withenv("DISTSSHKIT_YES" => nothing) do
            prev_ni = DistSSHKit.kit_noninteractive()
            DistSSHKit.set_kit_noninteractive!(false)
            try
                for v in (:quiet, :progress, :verbose)
                    with_kit_verbosity(v) do
                        out, result = _capture_stdio() do stdin_io, _
                            println(stdin_io, "n")
                            flush(stdin_io)
                            seekstart(stdin_io)
                            DistSSHKit.clone_to_remotes(
                                ["host1"], "~/App.jl", "git@example.com:org/App.jl.git",
                            )
                        end
                        @test result.cancelled && result.succeeded == 0 && result.failed == 0
                        @test occursin("Cancelled.", out)
                        @test occursin("Safety:", out)
                        @test occursin("Proceed?", out)
                    end
                end
            finally
                DistSSHKit.set_kit_noninteractive!(prev_ni)
            end
        end

        _with_fake_remotes() do _
            result = DistSSHKit.clone_to_remotes(
                ["host1"], "~/App.jl", "git@example.com:org/App.jl.git";
                confirm=false,
            )
            @test !result.cancelled && result.succeeded == 1 && result.failed == 0
            @test length(result.hosts) == 1 && result.hosts[1].ok
        end
        # Nonempty refuse: return value here; message text in setup/rsync.jl.
        # `_capture_stdio`: `print_err` ignores quiet, so otherwise a red ✗ leaks.
        _with_fake_remotes() do state_dir
            host = "host1"
            slot = replace(host, r"[@:/]" => "_")
            tree = joinpath(state_dir, slot, "tree")
            mkpath(tree)
            touch(joinpath(tree, "keepme.txt"))
            _, result = _capture_stdio() do _, _
                DistSSHKit.clone_to_remotes(
                    [host], "~/App.jl", "git@example.com:org/App.jl.git";
                    confirm=false,
                )
            end
            @test !result.cancelled && result.succeeded == 0 && result.failed == 1
            @test length(result.hosts) == 1 && !result.hosts[1].ok
        end
    end
end
