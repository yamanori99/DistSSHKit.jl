using Test

@testset "pool args" begin
    parse_pool_args = DistSSHKit.parse_pool_args

    @testset "parse_pool_args" begin
        let r = parse_pool_args(["parent", "child:host1", "child:host2"])
            @test !r.show_help
            @test r.include_parent
            @test r.hosts == ["host1", "host2"]
            @test r.gb_per_worker === nothing
            @test r.mem_headroom == DistSSHKit.DEFAULT_MEM_HEADROOM
            @test r.parent_gb == DistSSHKit.DEFAULT_PARENT_GB
        end
        let r = parse_pool_args(["child:local", "child:host1"])
            @test !r.include_parent
            @test r.hosts == ["local", "host1"]
        end
        @test_throws ArgumentError parse_pool_args(["--parent", "child:host1"])
        @test_throws ArgumentError parse_pool_args(["--masterhost", "child:host1"])
        @test_throws ArgumentError parse_pool_args(["--master-gb", "0.2"])
        @test_throws ArgumentError parse_pool_args(["--local", "child:host1"])
        @test_throws ArgumentError parse_pool_args(["--probe", "warmup.jl"])
        let r = parse_pool_args(["--hosts", "child:h1:4,child:h2", "child:host-cli"])
            @test r.hosts == ["host-cli", "h1", "h2"]
        end
        let r = parse_pool_args(["--gb-per-worker", "1.5", "child:host1"])
            @test r.gb_per_worker == 1.5
            @test r.hosts == ["host1"]
        end
        let r = parse_pool_args(["--mem-headroom", "0.5", "--parent-gb", "0.2"])
            @test r.mem_headroom == 0.5
            @test r.parent_gb == 0.2
        end
        let path = tempname()
            r = parse_pool_args(["--help"])
            @test r.show_help
            @test parse_pool_args(["-h"]).show_help
            open(path, "w") do io
                DistSSHKit.show_pool_usage(; io = io)
            end
            help = read(path, String)
            rm(path; force = true)
            @test occursin("DistSSHKit pool", help)
            @test occursin("parent", help)
            @test occursin("--gb-per-worker", help)
            @test !occursin("--probe PATH", help)
            @test occursin("size / size!", help)
            @test !occursin("--local", help)
            @test !occursin("#!/usr/bin/env julia", help)
        end
    end
end
