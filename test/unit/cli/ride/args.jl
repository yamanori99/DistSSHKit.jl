using Test

@testset "ride args" begin
    parse_ride_args = DistSSHKit.parse_ride_args

    let r = parse_ride_args(["parent:2", "job.jl", "--n", "4"])
        @test r.script_path == "job.jl"
        @test r.hosts == ["parent:2"]
        @test r.script_args == ["--n", "4"]
        @test r.spi_check
        @test !r.help
    end
    let r = parse_ride_args(["--no-spi-check", "job.jl"])
        @test !r.spi_check
    end
    let r = parse_ride_args(["parent:1", "child:host1:2", "--julia", "julia", "job.jl"])
        @test r.hosts == ["parent:1", "child:host1:2"]
        @test r.julia == "julia"
        @test r.script_path == "job.jl"
    end
    @test_throws ArgumentError parse_ride_args(["--analyze", "job.jl"])
    let path = tempname()
        @test parse_ride_args(["--help"]).help
        open(path, "w") do io
            DistSSHKit.show_ride_usage(; io = io)
        end
        help = read(path, String)
        rm(path; force = true)
        @test occursin("DistSSHKit ride", help)
        @test occursin("plan", help)
        @test occursin("child:", help)
        @test !occursin("--analyze", help)
        @test !occursin("#!/usr/bin/env julia", help)
    end
end
