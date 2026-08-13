using Test

@testset "go args" begin
    _go_dir = joinpath(_kit_root(), "src", "cli", "go")
    isdefined(Main, :parse_go_args) || include(joinpath(_go_dir, "args.jl"))

    @testset "help flags" begin
        @test parse_go_args(["--help"]).help
        @test parse_go_args(["-h"]).help
    end

    @testset "script and hosts" begin
        let r = parse_go_args(["demos/foo.jl", "8"])
            @test r.script_path == "demos/foo.jl"
            @test r.script_args == ["8"]
            @test isempty(r.hosts)
        end
        let r = parse_go_args(["user@lab", "job.jl"])
            @test r.script_path == "job.jl"
            @test r.hosts == ["user@lab"]
        end
        let r = parse_go_args(["--hosts", "host-a,host-b:2", "job.jl"])
            @test r.hosts == ["host-a", "host-b:2"]
            @test r.script_path == "job.jl"
        end
        let r = parse_go_args(["local:2", "h1", "job.jl", "4"])
            @test r.hosts == ["local:2", "h1"]
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
        let r = parse_go_args(["local:2", "h1", "job.jl"])
            @test r.sync === nothing
        end
        let r = parse_go_args(["--sync", "h1", "job.jl"])
            @test r.sync === :sync
        end
        let r = parse_go_args(["--rsync", "h1", "job.jl"])
            @test r.sync === :rsync
        end
        let r = parse_go_args(["--skip-sync", "local:1", "h1:2", "job.jl"])
            @test r.sync === false
            @test r.hosts == ["local:1", "h1:2"]
        end
        let r = parse_go_args(["--skip-git-guard", "h1", "job.jl"])
            @test r.sync === false  # go alias of --skip-sync
        end
        @test_throws ArgumentError parse_go_args(["--skip-sync", "--rsync", "job.jl"])
        @test_throws ArgumentError parse_go_args(["--sync", "--skip-git-guard", "job.jl"])
        @test_throws ArgumentError parse_go_args(["--sync", "--rsync", "job.jl"])
    end
end
