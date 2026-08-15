using Test
using DistSSHKit: CliCursor, cli_at_end, cli_consume!, cli_current, cli_take_value!

@testset "CliCursor" begin
    @testset "positional args" begin
        c = CliCursor(["host1", "host2"])
        @test cli_current(c) == "host1"
        cli_consume!(c)
        @test cli_current(c) == "host2"
        cli_consume!(c)
        @test cli_at_end(c)
    end

    @testset "cli_take_value!" begin
        c = CliCursor(["--julia", "/opt/julia/bin/julia"])
        @test cli_current(c) == "--julia"
        @test cli_take_value!(c, "--julia") == "/opt/julia/bin/julia"
        @test cli_at_end(c)
    end

    @testset "missing value" begin
        c = CliCursor(["--julia"])
        @test_throws ArgumentError cli_take_value!(c, "--julia")
    end
end
