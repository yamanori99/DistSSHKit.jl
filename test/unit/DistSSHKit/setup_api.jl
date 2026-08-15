using Test

@testset "setup!" begin
    function _with_fake_remotes(f::Function)
        _with_tempdir() do state_dir
            old_proj = get(ENV, "DISTRIBUTED_PROJECT_ROOT", nothing)
            old_remote = get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", nothing)
            try
                withenv(_fake_setup_remote_env(state_dir)...) do
                    _apply_quiet_setup_session!()
                    return f(state_dir)
                end
            finally
                if old_proj === nothing
                    delete!(ENV, "DISTRIBUTED_PROJECT_ROOT")
                else
                    ENV["DISTRIBUTED_PROJECT_ROOT"] = old_proj
                end
                if old_remote === nothing
                    delete!(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT")
                else
                    ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"] = old_remote
                end
            end
        end
    end

    @testset "delete + multi-mode" begin
        _with_fake_remotes() do state_dir
            _with_tempdir() do proj
                host = "host1"
                slot = replace(host, r"[@:/]" => "_")
                tree = joinpath(state_dir, slot, "tree")
                mkpath(tree)
                touch(joinpath(tree, "keepme.txt"))
                write(joinpath(proj, "Project.toml"), "name = \"Tmp\"\n")
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=[host],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                del = DistSSHKit.setup!(session, :delete)
                @test del.ok && !del.cancelled
                @test length(del.hosts) == 1 && del.hosts[1].ok
                @test !isdir(joinpath(state_dir, slot))

                # Fresh empty remote then rsync+instantiate path (fake rsync creates tree).
                chained = DistSSHKit.setup!(session, :rsync)
                @test chained isa DistSSHKit.SyncResult
                tested = DistSSHKit.setup!(session, :runtest; julia="/bin/echo")
                @test tested.ok && !tested.cancelled

                inst = DistSSHKit.setup!(session, :instantiate; julia="/bin/echo")
                @test inst.ok && !inst.cancelled
            end
        end
    end

    @testset "multi-mode stops after rsync refuse" begin
        _with_fake_remotes() do state_dir
            _with_tempdir() do proj
                write(joinpath(proj, "Project.toml"), "name = \"Tmp\"\n")
                host = "host1"
                slot = replace(host, r"[@:/]" => "_")
                tree = joinpath(state_dir, slot, "tree")
                mkpath(tree)
                touch(joinpath(tree, "keepme.txt"))
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=[host],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                _, res = _capture_stdio() do _, _
                    DistSSHKit.setup!(session, :rsync, :instantiate)
                end
                @test !res.ok
                # Nonempty tree still there: instantiate must not have been the stop reason.
                @test isfile(joinpath(tree, "keepme.txt"))
            end
        end
    end

    @testset "instantiate preflight miss" begin
        _with_fake_remotes() do _
            _with_tempdir() do proj
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["host1"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                withenv("DISTSSHKIT_TEST_SSH_FAIL" => "1") do
                    res = DistSSHKit.setup!(session, :instantiate; julia="/bin/echo")
                    @test !res.ok
                end
            end
        end
    end

    @testset "clone requires repo=" begin
        _with_tempdir() do proj
            session = DistSSHKit.KitSession(
                project=proj,
                workers=["host1"],
                remote="~/App.jl",
                yes=true,
            )
            @test_throws ArgumentError DistSSHKit.setup!(session, :clone)
            @test_throws ArgumentError DistSSHKit.setup!(session, :clone; repo="")
        end

        _with_fake_remotes() do _
            _with_tempdir() do proj
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["host1"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                res = DistSSHKit.setup!(session, :clone; repo="https://github.com/example/App.jl.git")
                @test res.ok && !res.cancelled
                @test length(res.hosts) == 1 && res.hosts[1].ok
            end
        end
    end

    @testset "check + cleanup + bad mode" begin
        _with_fake_remotes() do _
            _with_tempdir() do proj
                write(joinpath(proj, "Project.toml"), "name = \"Tmp\"\nuuid = \"00000000-0000-0000-0000-000000000001\"\n")
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["host1"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                out, res = _capture_stdio() do _, _
                    DistSSHKit.setup!(session, :check; check_code_sync=false, ignore_julia_version=true)
                end
                @test res isa DistSSHKit.SyncResult
                @test !res.cancelled
                @test !res.ok
                @test occursin("Prerequisites not met", out)

                @test_throws ArgumentError DistSSHKit.setup!(session, :nope)
                @test_throws ArgumentError DistSSHKit.setup!(session, :delete, :check; ignore_julia_version=true)
            end
        end

        _with_tempdir() do proj
            session = DistSSHKit.KitSession(
                project=proj,
                workers=["root@192.0.2.1"],
                remote="~/App.jl",
                yes=true,
                quiet=true,
            )
            clean = DistSSHKit.setup!(session, :cleanup)
            @test clean isa DistSSHKit.SyncResult
            @test !clean.cancelled
            @test length(clean.hosts) == 1
            @test !clean.hosts[1].ok
        end
    end
end
