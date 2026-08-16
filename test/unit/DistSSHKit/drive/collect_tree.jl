using Test

# Oracle: `collect!` skip / empty / rsync-invoke / rsync-fail wiring via setup
# SSH+rsync fakes. Fake rsync is `sh` `exit 0` (or 1); it does not copy bytes.
# Real collect of remote files is ssh-e2e.

@testset "drive collect_tree" begin
    function _seed_tree!(state_dir, host, rel)
        slot = replace(host, r"[@:/]" => "_")
        path = joinpath(state_dir, slot, "tree", rel)
        mkpath(dirname(path))
        write(path, "remote-bytes\n")
        return path
    end

    function _collect!(proj, out_dir, hosts; merge=false)
        session = DistSSHKit.KitSession(
            project=proj,
            workers=hosts,
            remote="/fake/remote/CollectHost",
        )
        return DistSSHKit.collect!(session, out_dir; merge=merge)
    end

    function _with_collect(f; extra_env=Dict{String,String}())
        _with_tempdir() do state_dir
            _with_tempdir() do proj
                write(joinpath(proj, "Project.toml"), "name = \"CollectHost\"\n")
                remote = "/fake/remote/CollectHost"
                env = merge(
                    _fake_setup_remote_env(state_dir),
                    Dict(
                        "DISTRIBUTED_PROJECT_ROOT" => proj,
                        "DISTRIBUTED_REMOTE_PROJECT_ROOT" => remote,
                    ),
                    extra_env,
                )
                withenv(env...) do
                    DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=true, yes=true))
                    DistSSHKit._ensure_drive_fragments!(proj)
                    return f(state_dir, proj)
                end
            end
        end
    end

    @testset "skip missing remote dir" begin
        _with_collect() do _, proj
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["host1"])
                end
                @test result.ok
                @test occursin("no directory on host", captured)
            end
        end
    end

    @testset "empty remote" begin
        _with_collect() do state_dir, proj
            mkpath(joinpath(state_dir, "host1", "tree"))
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["host1"])
                end
                @test result.ok
                @test occursin("no files found", captured)
            end
        end
    end

    @testset "collect-missing lists files and calls rsync" begin
        _with_collect() do state_dir, proj
            _seed_tree!(state_dir, "host1", joinpath("data", "a.txt"))
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["host1"])
                end
                @test result.ok
                @test occursin("1 file", captured)
                # Parents may be mkdir'd; fake rsync does not write the file.
                @test !isfile(joinpath(out_dir, "data", "a.txt"))
            end
        end
    end

    @testset "collect-missing skips existing" begin
        _with_collect() do state_dir, proj
            _seed_tree!(state_dir, "host1", "a.txt")
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            write(joinpath(out_dir, "a.txt"), "local\n")
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["host1"])
                end
                @test result.ok
                @test occursin("nothing new", captured)
                @test read(joinpath(out_dir, "a.txt"), String) == "local\n"
            end
        end
    end

    @testset "collect-overwrite calls rsync" begin
        _with_collect() do state_dir, proj
            _seed_tree!(state_dir, "host1", "a.txt")
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["host1"]; merge=true)
                end
                @test result.ok
                @test occursin("synced", captured)
                @test !isfile(joinpath(out_dir, "a.txt"))
            end
        end
    end

    @testset "rsync failure" begin
        _with_collect(; extra_env=Dict("DISTSSHKIT_TEST_RSYNC_FAIL" => "1")) do state_dir, proj
            _seed_tree!(state_dir, "host1", "a.txt")
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["host1"]; merge=true)
                end
                @test !result.ok
                @test result.exit_code == 1
                @test occursin("some hosts failed", captured)
            end
        end
    end
end
