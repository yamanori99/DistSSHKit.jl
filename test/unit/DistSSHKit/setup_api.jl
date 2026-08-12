using Test

@testset "setup!" begin
    function _with_fake_remotes(f::Function)
        mktempdir() do state_dir
            withenv(_fake_setup_remote_env(state_dir)...) do
                _apply_quiet_setup_session!()
                return f(state_dir)
            end
        end
    end

    @testset "delete + multi-mode" begin
        _with_fake_remotes() do state_dir
            mktempdir() do proj
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
            end
        end
    end

    @testset "clone requires repo=" begin
        mktempdir() do proj
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
            mktempdir() do proj
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
            mktempdir() do proj
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
                @test res.ok == false
                @test occursin("Prerequisites not met", out)

                @test_throws ArgumentError DistSSHKit.setup!(session, :nope)
                @test_throws ArgumentError DistSSHKit.setup!(session, :delete, :check; ignore_julia_version=true)
            end
        end

        mktempdir() do proj
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
