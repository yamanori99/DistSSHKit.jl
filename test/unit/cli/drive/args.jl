using Test

@testset "drive args" begin
    _drive_dir = joinpath(_kit_root(), "src", "cli", "drive")
    _runtime_dir = joinpath(_kit_root(), "src", "DistSSHKit", "drive", "runtime")
    isdefined(Main, :parse_drive_args) || include(joinpath(_drive_dir, "args.jl"))
    isdefined(Main, :check_memory_capacity) || include(joinpath(_runtime_dir, "checks.jl"))
    isdefined(Main, :drive_script_not_found_message) || include(joinpath(_runtime_dir, "_common.jl"))

    @test occursin("demo install", drive_script_not_found_message(
        joinpath(_kit_root(), "demos", "square_file.jl"),
        _kit_root(),
    ))

    @testset "collect modes" begin
        @test_throws ArgumentError parse_drive_args(["--collect", "h"])
        @test_throws ArgumentError parse_drive_args(["--collect-sync", "data/sweep", "host"])
        @test_throws ArgumentError parse_drive_args(["--collect-missing", "data/sweep"])

        let r = parse_drive_args(["--collect-missing", "data/sweep", "host-a", "host-b"])
            @test r.collect_root == abspath("data/sweep")
            @test r.collect_hosts == ["host-a", "host-b"]
            @test r.collect_overwrite == false
            @test r.script_path === nothing
        end
        let r = parse_drive_args(["--collect-overwrite", "data/sweep", "host-a"])
            @test r.collect_overwrite == true
            @test r.collect_hosts == ["host-a"]
        end
    end

    @testset "parse hosts and flags" begin
        @test _parse_host_workers_spec("host-a") == ("host-a", nothing)
        @test _parse_host_workers_spec("host-a:10") == ("host-a", 10)

        withenv("JULIA_DISTRIBUTED_EXE" => nothing) do
            let r = parse_drive_args(["--help"])
                @test r.help == true
            end
            let r = parse_drive_args(["--local", "4", "myscript.jl", "a", "b"])
                @test r.local_workers == 4
                @test r.script_path == "myscript.jl"
                @test r.script_args == ["a", "b"]
            end
            # One local-alias form; DistSSHKit/hosts.jl covers the predicate set.
            let r = parse_drive_args(["local:3", "host1:2", "s.jl"])
                @test r.local_workers == 3
                @test r.hosts == [("host1", 2)]
            end
            @test_throws ArgumentError parse_drive_args(["--local", "2", "local:2", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["--local", "s.jl"])

            let r = parse_drive_args(["--workers", "3", "host1", "host2:5", "s.jl"])
                @test r.default_workers == 3
                @test r.hosts == [("host1", nothing), ("host2", 5)]
            end
            let r = parse_drive_args(["--julia", "/usr/bin/julia", "s.jl"])
                @test r.julia == "/usr/bin/julia"
            end
            let r = parse_drive_args(["--julia", "auto", "s.jl"])
                @test r.julia === nothing
            end
            let r = parse_drive_args(["--no-log", "s.jl"])
                @test r.enable_log == false
            end
            let r = parse_drive_args(["--log-dir", "/tmp/logs", "--output-dir", "/tmp/out", "s.jl"])
                @test r.log_dir == "/tmp/logs"
                @test r.output_dir == "/tmp/out"
            end
            let r = parse_drive_args(["--package", "MyPkg", "s.jl"])
                @test r.explicit_package == "MyPkg"
            end
            let r = parse_drive_args(["--package", "  ", "s.jl"])
                @test r.explicit_package === nothing
            end
            let r = parse_drive_args(["--version"])
                @test r.show_version == true
            end
            hosts_file = _sample_hosts_file()
            let r = parse_drive_args(["--hosts-file", hosts_file, "host-cli:2", "s.jl"])
                @test r.hosts == [("host-cli", 2), ("host-a", nothing), ("host-b", 4)]
            end
            let r = parse_drive_args(["-q", "-y", "s.jl"])
                @test r.cli_session.quiet == true
                @test r.cli_session.yes == true
                DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession())
            end
            withenv("DISTSSHKIT_HOSTS" => "env-host:3, env-b") do
                let r = parse_drive_args(["local:2", "s.jl"])
                    @test r.local_workers == 2
                    @test ("env-host", 3) in r.hosts
                    @test ("env-b", nothing) in r.hosts
                end
            end
            let r = parse_drive_args(String[])
                @test r.script_path === nothing
            end
        end
        withenv("JULIA_DISTRIBUTED_EXE" => "/opt/custom/julia") do
            let r = parse_drive_args(["s.jl"])
                @test r.julia == "/opt/custom/julia"
            end
        end
    end

    @testset "sync and git parity" begin
        # Two axes: pre-run sync (--sync/--rsync) and git parity (--require-git).
        # Defaults: no sync, no parity (skip_hash_check=true).
        let r = parse_drive_args(["s.jl"])
            @test r.sync_mode === nothing
            @test r.skip_hash_check == true
        end
        let r = parse_drive_args(["--sync", "host1", "s.jl"])
            @test r.sync_mode === :sync
            @test r.skip_hash_check == true
        end
        let r = parse_drive_args(["--rsync", "s.jl"])
            @test r.sync_mode === :rsync
            @test r.skip_hash_check == true
        end
        let r = parse_drive_args(["--require-git", "host1", "s.jl"])
            @test r.sync_mode === nothing
            @test r.skip_hash_check == false
        end
        let r = parse_drive_args(["--require-git", "--sync", "host1", "s.jl"])
            @test r.sync_mode === :sync
            @test r.skip_hash_check == false
        end
        # Compat no-op; independent of sync axis
        let r = parse_drive_args(["--skip-git-guard", "s.jl"])
            @test r.sync_mode === nothing
            @test r.skip_hash_check == true
        end
        let r = parse_drive_args(["--sync", "--skip-git-guard", "host1", "s.jl"])
            @test r.sync_mode === :sync
            @test r.skip_hash_check == true
        end
        @test_throws ArgumentError parse_drive_args(["--sync", "--rsync", "s.jl"])
        @test_throws ArgumentError parse_drive_args(["--require-git", "--rsync", "s.jl"])
        @test_throws ArgumentError parse_drive_args(["--rsync", "--require-git", "s.jl"])
        @test_throws ArgumentError parse_drive_args(["--require-git", "--skip-git-guard", "s.jl"])
        @test_throws ArgumentError parse_drive_args(["--sync", "--collect-missing", "out", "h1"])
    end

    @testset "help smoke" begin
        txt = drive_help_text()
        @test occursin("Usage:", txt)
        @test occursin("--collect-missing", txt)
        @test occursin("--quiet", txt)
        @test occursin("--require-git", txt)
        @test occursin("--sync", txt)
        @test occursin("--rsync", txt)
        @test occursin("post-run-new", txt) || occursin("slot-overwrite", DistSSHKit.COLLECT_MODE_HELP)
        # Story: parity is opt-in, not required after rsync
        @test occursin("off by default", lowercase(txt)) || occursin("Default is off", txt)
        @test !occursin("required after `setup --rsync`", txt)
    end

    @testset "check_git_hashes" begin
        function _init_git_repo!(d::String)
            run(Cmd(["git", "-C", d, "init", "-q"]))
            run(Cmd(["git", "-C", d, "config", "user.email", "test@example.com"]))
            run(Cmd(["git", "-C", d, "config", "user.name", "Test"]))
            write(joinpath(d, "f.txt"), "hi")
            run(Cmd(["git", "-C", d, "add", "f.txt"]))
            run(Cmd(["git", "-C", d, "commit", "-q", "-m", "init"]))
        end

        function _check_git(hosts, d)
            DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=true, yes=true))
            return check_git_hashes(hosts, d)
        end

        mktempdir() do tmp
            d = abspath(string(tmp))
            ok, mismatches, unverifiable = _check_git(String[], d)
            @test ok && isempty(mismatches) && isempty(unverifiable)
        end
        mktempdir() do tmp
            d = abspath(string(tmp))
            _init_git_repo!(d)
            ok, mismatches, unverifiable = _check_git(String[], d)
            @test ok && isempty(mismatches) && isempty(unverifiable)
        end
        mktempdir() do tmp
            d = abspath(string(tmp))
            _init_git_repo!(d)
            ok, mismatches, unverifiable = _check_git(["no-such-host.invalid"], d)
            @test ok == false
            @test isempty(mismatches)
            @test unverifiable == ["no-such-host.invalid"]
        end
    end
end
