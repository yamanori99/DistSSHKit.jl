using Test

@testset "drive args" begin
    parse_drive_args = DistSSHKit.parse_drive_args
    drive_help_text = DistSSHKit.drive_help_text

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
        @test DistSSHKit.split_worker_token("host-a") == ("host-a", nothing)
        @test DistSSHKit.split_worker_token("host-a:10") == ("host-a", 10)

        withenv("JULIA_DISTRIBUTED_EXE" => nothing) do
            let r = parse_drive_args(["--help"])
                @test r.help == true
            end
            let r = parse_drive_args(["-h"])
                @test r.help == true
            end
            let r = parse_drive_args(["s.jl"])
                @test r.hint_surface === :cli
            end
            let r = parse_drive_args(["parenthost:4", "myscript.jl", "a", "b"])
                @test r.local_workers == 4
                @test r.script_path == "myscript.jl"
                @test r.script_args == ["a", "b"]
            end
            @test_throws ArgumentError parse_drive_args(["--parenthost", "4", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["--parenthost:5", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["--masterhost", "4", "s.jl"])
            let r = parse_drive_args(["parenthost:3", "host1:2", "s.jl"])
                @test r.local_workers == 3
                @test r.hosts == [("host1", 2)]
                @test DistSSHKit.host_tokens(r; kind=:drive) == ["parenthost:3", "host1:2"]
            end
            let r = parse_drive_args(["parenthost:4", "host1", "host2:2", "s.jl"])
                @test DistSSHKit.host_tokens(r; kind=:drive) == ["parenthost:4", "host1", "host2:2"]
            end
            @test_throws ArgumentError parse_drive_args(["--local", "4", "myscript.jl", "a", "b"])
            @test_throws ArgumentError parse_drive_args(["--local:5", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["-l:2", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["-l", "3", "s.jl"])
            let r = parse_drive_args(["--workers:7", "host1", "s.jl"])
                @test r.default_workers == 7
                @test r.hosts == [("host1", nothing)]
                @test DistSSHKit.host_tokens(r; kind=:drive) == ["host1"]
            end
            let r = parse_drive_args(["-w:4", "host1", "s.jl"])
                @test r.default_workers == 4
            end
            let r = parse_drive_args(["local:3", "host1:2", "s.jl"])
                @test r.local_workers == 0
                @test r.hosts == [("local", 3), ("host1", 2)]
                @test DistSSHKit.host_tokens(r; kind=:drive) == ["local:3", "host1:2"]
            end
            let r = parse_drive_args(["localhost:4", "s.jl"])
                @test r.local_workers == 0
                @test r.hosts == [("localhost", 4)]
            end
            @test_throws ArgumentError parse_drive_args(["--local", "2", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["--local:"])
            @test_throws ArgumentError parse_drive_args(["--workers", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["--workers", "x", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["--nope", "s.jl"])
            @test_throws ArgumentError parse_drive_args(["--julia"])
            @test_throws ArgumentError parse_drive_args(["--require-git", "--require-git", "s.jl"])

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
            let r = parse_drive_args(["--hosts", "h-csv:2,h-csv-b", "s.jl"])
                @test r.hosts == [("h-csv", 2), ("h-csv-b", nothing)]
            end
            let r = parse_drive_args(["-q", "-y", "s.jl"])
                @test r.cli_session.quiet == true
                @test r.cli_session.yes == true
                DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession())
            end
            withenv("DISTSSHKIT_HOSTS" => "env-host:3, env-b") do
                let r = parse_drive_args(["parenthost:2", "s.jl"])
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
        # Duplicate same sync flag is a no-op (only mixed flags throw).
        let r = parse_drive_args(["--sync", "--sync", "host1", "s.jl"])
            @test r.sync_mode === :sync
        end
        @test_throws ArgumentError parse_drive_args(["host1", "--collect-missing", "out", "h1"])
        # Shared flags are peeled even after `--collect-missing` (not treated as HOST).
        let r = parse_drive_args(["--collect-missing", "out", "--quiet", "h1"])
            @test r.collect_hosts == ["h1"]
            @test r.cli_session.quiet
            DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession())
        end
        @test_throws ArgumentError parse_drive_args(["--collect-missing", "out", "--foo", "h1"])
        @test_throws ArgumentError parse_drive_args(["--collect-overwrite"])
    end

    @testset "help smoke" begin
        txt = drive_help_text()
        @test occursin("Usage", txt)
        @test occursin("--collect-missing", txt)
        @test occursin("--quiet", txt)
        @test occursin("--hosts", txt)
        @test occursin("--require-git", txt)
        @test occursin("--sync", txt)
        @test occursin("--rsync", txt)
        @test occursin("post-run-new", txt)
        @test occursin("off by default", lowercase(txt))
        @test occursin("parenthost:N", txt)
        @test !occursin("--parenthost", txt)
        @test !occursin("--local", txt)
        @test occursin("DISTSSHKIT_JOBS", txt)
        @test occursin("DISTSSHKIT_REQUIRE_ALL_HOSTS", txt)
        @test !occursin("required after `setup --rsync`", txt)
    end

    @testset "require-all-hosts" begin
        withenv("DISTSSHKIT_REQUIRE_ALL_HOSTS" => nothing) do
            @test !parse_drive_args(["s.jl"]).require_all_hosts
            @test parse_drive_args(["--require-all-hosts", "s.jl"]).require_all_hosts
            @test_throws ArgumentError parse_drive_args(
                ["--require-all-hosts", "--require-all-hosts", "s.jl"],
            )
            let r = parse_drive_args(["--require-all-hosts", "--collect-missing", "out", "h1"])
                @test r.require_all_hosts
            end
        end
        withenv("DISTSSHKIT_REQUIRE_ALL_HOSTS" => "1") do
            @test parse_drive_args(["s.jl"]).require_all_hosts
        end
    end
end
