using Test

# Module setup rsync / clone dest messaging (CLI exit codes in integration/setup/exit.jl).

@testset "setup rsync" begin
    remote_path = "~/App.jl"
    project = _kit_root()

    function _with_fake_remotes(f::Function; extra_env=Dict{String,String}())
        _with_tempdir() do state_dir
            withenv(merge(_fake_setup_remote_env(state_dir), extra_env)...) do
                _apply_quiet_setup_session!()
                return f(state_dir)
            end
        end
    end

    function _mark_nonempty!(state_dir::AbstractString, host::AbstractString)
        slot = replace(host, r"[@:/]" => "_")
        tree = joinpath(state_dir, slot, "tree")
        mkpath(tree)
        touch(joinpath(tree, "keepme.txt"))
    end

    @testset "remote_dir / ensure" begin
        _with_fake_remotes() do _
            host = "user@host.test"
            @test DistSSHKit.remote_dir_exists(host, remote_path) == false
            @test DistSSHKit.ensure_remote_dir(host, remote_path) == true
            @test DistSSHKit.remote_dest_status(host, remote_path) === :empty
        end
        _with_fake_remotes(extra_env=Dict("DISTSSHKIT_TEST_MKDIR_FAIL" => "1")) do _
            @test DistSSHKit.ensure_remote_dir("user@host.test", remote_path) == false
        end
    end

    @testset "rsync outcomes" begin
        withenv("DISTSSHKIT_YES" => nothing) do
            prev_ni = DistSSHKit.kit_noninteractive()
            DistSSHKit.set_kit_noninteractive!(false)
            try
                for v in (:quiet, :progress, :verbose)
                    with_kit_verbosity(v) do
                        out, result = _capture_stdio() do stdin_io, _
                            println(stdin_io, "")
                            flush(stdin_io)
                            seekstart(stdin_io)
                            DistSSHKit.rsync_push_to_remotes(["host1"], remote_path, project)
                        end
                        @test result == (cancelled=true, succeeded=0, failed=0)
                        @test occursin("Cancelled.", out)
                        @test occursin("bypasses git", out)
                        @test occursin("Type 'rsync'", out)
                    end
                end
            finally
                DistSSHKit.set_kit_noninteractive!(prev_ni)
            end
        end

        _with_fake_remotes(extra_env=Dict("DISTSSHKIT_TEST_MKDIR_FAIL" => "1")) do _
            raw = DistSSHKit.rsync_project_to_hosts!(
                ["host1"], project, remote_path; confirm=false, report=false,
            )
            @test raw.succeeded == 0 && raw.failed == 1
        end

        _with_fake_remotes() do _
            raw = DistSSHKit.rsync_project_to_hosts!(
                ["host1"], project, remote_path; confirm=false, report=false,
            )
            @test raw.succeeded == 1 && raw.failed == 0
        end

        _with_fake_remotes() do _
            withenv("DISTSSHKIT_JOBS" => "2") do
                raw = DistSSHKit.rsync_project_to_hosts!(
                    ["host1", "host2"], project, remote_path; confirm=false, report=false,
                )
                @test raw.succeeded == 2 && raw.failed == 0
                @test [hr.host for hr in raw.host_results] == ["host1", "host2"]
            end
        end

        _with_fake_remotes() do state_dir
            host = "user@host.test"
            _mark_nonempty!(state_dir, host)
            DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=false, yes=true))
            out, result = _capture_stdio() do _, _
                DistSSHKit.rsync_push_to_remotes([host], remote_path, project)
            end
            @test result == (cancelled=false, succeeded=0, failed=1)
            @test occursin("refusing to overwrite", out)
        end

        _with_fake_remotes(extra_env=Dict("DISTSSHKIT_TEST_RSYNC_FAIL" => "1")) do _
            raw = DistSSHKit.rsync_project_to_hosts!(
                ["host1"], project, remote_path; confirm=false, report=false,
            )
            @test raw.succeeded == 0 && raw.failed == 1
        end
    end
end

@testset "setup clone dest safety" begin
    remote_path = "~/App.jl"

    _with_tempdir() do state_dir
        withenv(_fake_setup_remote_env(state_dir)...) do
            DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=false, yes=true))
            host = "host1"
            slot = replace(host, r"[@:/]" => "_")
            tree = joinpath(state_dir, slot, "tree")
            mkpath(tree)
            touch(joinpath(tree, "keepme.txt"))
            out, result = _capture_stdio() do _, _
                DistSSHKit.clone_to_remotes(
                    [host], remote_path, "git@example.com:org/App.jl.git",
                )
            end
            @test !result.cancelled && result.succeeded == 0 && result.failed == 1
            @test length(result.hosts) == 1 && !result.hosts[1].ok
            @test occursin("refusing to overwrite", out)
            @test isfile(joinpath(tree, "keepme.txt"))
        end
    end
end
