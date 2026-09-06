using Test

@testset "plan args" begin
    parse_plan_args = DistSSHKit.parse_plan_args

    @testset "help and script" begin
        @test parse_plan_args(["--help"]).show_help
        @test parse_plan_args(["-h"]).show_help
        let r = parse_plan_args(["job.jl"])
            @test r.script_path == "job.jl"
            @test !r.show_help
            @test !r.show_version
        end
        let r = parse_plan_args(["--version"])
            @test r.show_version
            @test r.script_path === nothing
        end
        let r = parse_plan_args(["parent", "--gb-per-worker", "1.5", "job.jl"])
            @test r.script_path == "job.jl"
            @test r.tokens == ["parent"]
            @test r.gb_per_worker == 1.5
        end
        let r = parse_plan_args(["--probe", "warm.jl", "job.jl"])
            @test r.probe == "warm.jl"
            @test r.script_path == "job.jl"
        end
        @test_throws ArgumentError parse_plan_args(["a.jl", "b.jl"])
        @test_throws ArgumentError parse_plan_args(["job.jl", "extra"])
        let r = @test_logs (:warn, r"Unknown option") parse_plan_args(["--nope", "job.jl"])
            @test r.script_path == "job.jl"
        end
    end
end
