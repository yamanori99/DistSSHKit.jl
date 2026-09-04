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
                    workers=["child:$host"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                del = DistSSHKit.setup!(session, :delete)
                @test del.ok && !del.cancelled
                @test length(del.hosts) == 1 && del.hosts[1].ok
                @test !isdir(joinpath(state_dir, slot))
                prog = joinpath(proj, ".distsshkit", "setup", "kit.progress")
                @test isfile(prog)
                body = read(prog, String)
                @test occursin("kind=setup", body)
                @test occursin("label=delete/$host", body)

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

    @testset "prune leaves" begin
        _with_tempdir() do proj
            go_old = joinpath(proj, ".distsshkit", "go", "job_20200101T000000Z")
            go_keep = joinpath(proj, "scripts", ".distsshkit", "go", "job_keep_id")
            drive = joinpath(proj, "scripts", ".distsshkit", "drive")
            mkpath(go_old)
            mkpath(go_keep)
            mkpath(drive)
            write(joinpath(proj, "Project.toml"), "name = \"Tmp\"\n")
            n = DistSSHKit.prune_kit_leaf_dirs!(proj; id="keep_id")
            @test n == 1
            @test isdir(go_old)
            @test !isdir(go_keep)
            @test isdir(drive)
            n2 = DistSSHKit.prune_kit_leaf_dirs!(proj)
            @test n2 >= 2
            @test !isdir(go_old)
            @test !isdir(drive)
            @test isfile(joinpath(proj, "Project.toml"))
        end

        _with_fake_remotes() do state_dir
            _with_tempdir() do proj
                host = "host1"
                slot = replace(host, r"[@:/]" => "_")
                tree = joinpath(state_dir, slot, "tree")
                mkpath(joinpath(tree, ".distsshkit", "go", "batch_a"))
                mkpath(joinpath(tree, "keep"))
                write(joinpath(tree, "keep", "Project.toml"), "name = \"Tmp\"\n")
                write(joinpath(proj, "Project.toml"), "name = \"Tmp\"\n")
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["child:$host"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                pr = DistSSHKit.setup!(session, :prune)
                @test pr.ok && !pr.cancelled
                @test isfile(joinpath(tree, "keep", "Project.toml"))
                @test !isdir(joinpath(tree, ".distsshkit", "go", "batch_a"))
            end
        end
    end

    @testset "juliaup align" begin
        _with_fake_remotes() do _
            _with_tempdir() do proj
                write(joinpath(proj, "Project.toml"), "name = \"Tmp\"\n")
                host = "host1"
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["child:$host"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                empty!(DistSSHKit._DETECT_JULIA_PATH_CACHE)
                ver_env = Dict(
                    "DISTSSHKIT_TEST_JULIA_VERSION" => "julia version $(VERSION)",
                    "DISTSSHKIT_TEST_UNAME" => "Linux",
                )
                withenv(ver_env...) do
                    up = DistSSHKit.setup!(session, :juliaup)
                    @test up.ok && !up.cancelled
                    @test length(up.hosts) == 1 && up.hosts[1].ok
                end
                withenv("DISTSSHKIT_TEST_NO_JULIAUP" => "1") do
                    empty!(DistSSHKit._DETECT_JULIA_PATH_CACHE)
                    bad = DistSSHKit.setup!(session, :juliaup)
                    @test !bad.ok
                end
            end
        end
    end

    @testset "quiet suppresses Log file on stdout" begin
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
                    workers=["child:$host"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                with_kit_verbosity(:verbose) do
                    out, del = _capture_stdio() do _, _
                        DistSSHKit.setup!(session, :delete)
                    end
                    @test del.ok && !del.cancelled
                    @test !occursin("Log file:", out)
                    @test isfile(joinpath(proj, ".distsshkit", "setup", "kit.progress"))
                end
            end
        end
    end

    @testset "ambient progress keeps Log file off stdout" begin
        _with_fake_remotes() do _
            _with_tempdir() do proj
                write(joinpath(proj, "Project.toml"), "name = \"Tmp\"\n")
                # No quiet=: auto session would resolve to :verbose under a pipe.
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["child:host1"],
                    remote="~/App.jl",
                    yes=true,
                )
                with_kit_verbosity(:progress) do
                    out, _ = _capture_stdio() do _, _
                        DistSSHKit.setup!(session, :cleanup)
                    end
                    @test !occursin("Log file:", out)
                    @test DistSSHKit.kit_verbosity() === :progress
                end
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
                    workers=["child:$host"],
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
                    workers=["child:host1"],
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
                workers=["child:host1"],
                remote="~/App.jl",
                yes=true,
            )
            out, _ = _capture_stdio() do _, _
                @test_throws ArgumentError DistSSHKit.setup!(session, :clone)
                @test_throws ArgumentError DistSSHKit.setup!(session, :clone; repo="")
            end
            @test !occursin("Log file:", out)
            @test !isdir(joinpath(proj, ".distsshkit", "setup"))
        end

        _with_fake_remotes() do _
            _with_tempdir() do proj
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["child:host1"],
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
                    workers=["child:host1"],
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
                @test !occursin("Log file:", out)

                @test_throws ArgumentError DistSSHKit.setup!(session, :nope)
                @test_throws ArgumentError DistSSHKit.setup!(session, :delete, :check; ignore_julia_version=true)
            end
        end

        _with_fake_remotes() do _
            _with_tempdir() do proj
                session = DistSSHKit.KitSession(
                    project=proj,
                    workers=["child:host1"],
                    remote="~/App.jl",
                    yes=true,
                    quiet=true,
                )
                withenv("DISTSSHKIT_TEST_SSH_FAIL" => "1") do
                    clean = DistSSHKit.setup!(session, :cleanup)
                    @test clean isa DistSSHKit.SyncResult
                    @test !clean.cancelled
                    @test length(clean.hosts) == 1
                    @test !clean.hosts[1].ok
                end
            end
        end
    end
end
