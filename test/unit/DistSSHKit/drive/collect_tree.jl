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
                    _collect!(proj, out_dir, ["child:host1"])
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
                    _collect!(proj, out_dir, ["child:host1"])
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
                    _collect!(proj, out_dir, ["child:host1"])
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
                    _collect!(proj, out_dir, ["child:host1"])
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
                    _collect!(proj, out_dir, ["child:host1"]; merge=true)
                end
                @test result.ok
                @test occursin("synced", captured)
                @test !isfile(joinpath(out_dir, "a.txt"))
            end
        end
    end

    @testset "rsync failure" begin
        # Nested fake-ssh Julia + collect rsync-fail OOMs 1.11 on GHA (1.10/1.12 ok).
        if v"1.11" <= VERSION < v"1.12"
            @test_skip "1.11 GHA OOM on collect rsync-fail"
            return
        end
        _with_collect(; extra_env=Dict("DISTSSHKIT_TEST_RSYNC_FAIL" => "1")) do state_dir, proj
            _seed_tree!(state_dir, "host1", "a.txt")
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["child:host1"]; merge=true)
                end
                @test !result.ok
                @test result.exit_code == 1
                @test occursin("some hosts failed", captured)
            end
        end
    end

    @testset "collect-missing find failure is not empty success" begin
        _with_collect(; extra_env=Dict("DISTSSHKIT_TEST_FIND_FAIL" => "1")) do state_dir, proj
            mkpath(joinpath(state_dir, "host1", "tree"))
            write(joinpath(state_dir, "host1", "tree", "a.txt"), "x\n")
            out_dir = joinpath(proj, "out")
            mkpath(out_dir)
            with_kit_verbosity(:verbose) do
                captured, result = _capture_stdio() do _, _
                    _collect!(proj, out_dir, ["child:host1"])
                end
                @test !result.ok
                @test !occursin("no files found", captured)
                @test occursin("some hosts failed", captured)
            end
        end
    end

    @testset "post-run find failure sets HostRunResult" begin
        _with_collect(; extra_env=Dict("DISTSSHKIT_TEST_FIND_FAIL" => "1")) do state_dir, proj
            mkpath(joinpath(state_dir, "host1", "tree"))
            script = joinpath(proj, "job.jl")
            write(script, "true\n")
            out = joinpath(proj, "out")
            mkpath(out)
            withenv("DISTRIBUTED_OUTPUT_DIR" => out) do
                ok, hrs = Main.collect_drive_results!(
                    ["host1"], dirname(script), ".drive_sentinel_x", false, proj,
                )
                @test !ok
                @test length(hrs) == 1
                @test !hrs[1].ok
            end
        end
    end

    @testset "skip_collect does not place sentinels" begin
        _with_collect() do state_dir, proj
            logp = joinpath(state_dir, "ssh.log")
            script = joinpath(proj, "job.jl")
            write(script, "true\n")
            withenv("DISTSSHKIT_TEST_SSH_LOG" => logp) do
                name = Main.place_drive_sentinels!(["host1"], dirname(script), true)
                @test name == ""
            end
            @test !isfile(logp) || !occursin("mkdir", read(logp, String))
        end
    end
end
