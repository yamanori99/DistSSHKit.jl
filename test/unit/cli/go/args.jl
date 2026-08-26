using Test

@testset "go args" begin
    parse_go_args = DistSSHKit.parse_go_args

    @testset "help flags" begin
        @test parse_go_args(["--help"]).help
        @test parse_go_args(["-h"]).help
        let r = parse_go_args([
                "--julia", "/opt/julia/bin/julia",
                "--output-dir", "my_runs",
                "--sync", "child:h1",
                "--help",
            ])
            @test r.help
            @test r.julia == "/opt/julia/bin/julia"
            @test r.output_dir == "my_runs"
            @test r.sync === :sync
            @test r.hosts == ["child:h1"]
        end
    end

    @testset "script and hosts" begin
        let r = parse_go_args(["demos/foo.jl", "8"])
            @test r.script_path == "demos/foo.jl"
            @test r.script_args == ["8"]
            @test isempty(r.hosts)
        end
        let r = parse_go_args(["child:user@lab", "job.jl"])
            @test r.script_path == "job.jl"
            @test r.hosts == ["child:user@lab"]
        end
        let r = parse_go_args(["--hosts", "child:host-a,child:host-b:2", "job.jl"])
            @test r.hosts == ["child:host-a", "child:host-b:2"]
            @test r.script_path == "job.jl"
        end
        @test_throws ArgumentError parse_go_args(["user@lab", "job.jl"])
        let r = parse_go_args(["parent:4", "child:host1", "child:host2:2", "job.jl"])
            @test DistSSHKit.host_tokens(r; kind=:go) == ["parent:4", "child:host1", "child:host2:2"]
        end
        let r = parse_go_args(["child:local:2", "child:h1", "job.jl", "4"])
            @test r.hosts == ["child:local:2", "child:h1"]
            @test DistSSHKit.host_tokens(r; kind=:go) == ["child:local:2", "child:h1"]
            @test DistSSHKit.host_tokens(r.hosts) == ["child:local:2", "child:h1"]
            @test_throws ArgumentError DistSSHKit.host_tokens(r; kind=:pipeline)
            @test r.script_path == "job.jl"
            @test r.script_args == ["4"]
        end
        let r = parse_go_args(["--output-dir", "my_runs", "job.jl"])
            @test r.output_dir == "my_runs"
            @test r.script_path == "job.jl"
        end
        let r = parse_go_args(["--julia", "/opt/julia/bin/julia", "job.jl"])
            @test r.julia == "/opt/julia/bin/julia"
            @test r.script_path == "job.jl"
        end
        let r = parse_go_args(["--julia", "auto", "job.jl"])
            @test r.julia === nothing
        end
        withenv("JULIA_DISTRIBUTED_EXE" => "/env/julia") do
            let r = parse_go_args(["job.jl"])
                @test r.julia == "/env/julia"
            end
            let r = parse_go_args(["--julia", "auto", "job.jl"])
                @test r.julia === nothing
            end
        end
    end

    @testset "sync flags" begin
        # Parser leaves sync=nothing; go! maps nothing → false (no pre-run sync).
        let r = parse_go_args(["child:local:2", "child:h1", "job.jl"])
            @test r.sync === nothing
        end
        let r = parse_go_args(["--sync", "child:h1", "job.jl"])
            @test r.sync === :sync
        end
        let r = parse_go_args(["--rsync", "child:h1", "job.jl"])
            @test r.sync === :rsync
        end
        let r = parse_go_args(["--skip-sync", "child:local:1", "child:h1:2", "job.jl"])
            @test r.sync === false
            @test r.hosts == ["child:local:1", "child:h1:2"]
        end
        let r = parse_go_args(["--skip-git-guard", "child:h1", "job.jl"])
            @test r.sync === false  # go alias of --skip-sync
        end
        @test_throws ArgumentError parse_go_args(["--skip-sync", "--rsync", "job.jl"])
        @test_throws ArgumentError parse_go_args(["--sync", "--skip-git-guard", "job.jl"])
        @test_throws ArgumentError parse_go_args(["--sync", "--rsync", "job.jl"])
    end

    @testset "version, quiet, and hosts env" begin
        let r = parse_go_args(["--version"])
            @test r.show_version
        end
        let r = parse_go_args(["-q", "-y", "job.jl"])
            @test r.cli_session.quiet
            @test r.cli_session.yes
            DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession())
        end
        withenv("DISTSSHKIT_HOSTS" => "child:env-a:2,child:env-b") do
            let r = parse_go_args(["job.jl"])
                @test r.hosts == ["child:env-a:2", "child:env-b"]
            end
        end
        @test_throws ArgumentError parse_go_args(["--output-dir"])
        @test_throws ArgumentError parse_go_args(["--julia"])
    end

    @testset "help smoke" begin
        txt = sprint(io -> DistSSHKit.show_go_usage(; io=io))
        @test occursin("Usage", txt)
        @test occursin("--output-dir", txt)
        @test occursin("--sync", txt)
        @test occursin("empty path", txt)
        @test occursin("instantiates missing deps", txt)
        @test occursin("--hosts", txt)
        @test occursin("parent", txt)
        @test occursin("progress DIR", txt)
    end

    @testset "unknown option and missing script" begin
        @test_throws ArgumentError parse_go_args(["--nope"])
        let r = parse_go_args(["child:h1"])
            @test r.script_path === nothing
            @test r.hosts == ["child:h1"]
            @test !r.help
        end
        mktemp() do path, io
            code = withenv("DISTSSHKIT_CLI_SUBCOMMAND_DONE" => "") do
                redirect_stderr(devnull) do
                    redirect_stdout(io) do
                        DistSSHKit.go(String[])
                    end
                end
            end
            flush(io)
            @test code == 0
            @test occursin("SCRIPT.jl", read(path, String))
        end
    end

    @testset "--hosts-file keeps host:N" begin
        hosts_file = _sample_hosts_file()
        withenv("DISTSSHKIT_HOSTS" => nothing, "DISTSSHKIT_HOSTS_FILE" => nothing) do
            let r = parse_go_args(["--hosts-file", hosts_file, "job.jl"])
                @test r.hosts == ["child:host-a", "child:host-b:4"]
                @test r.script_path == "job.jl"
            end
        end
    end
end
