# A client `qhost:` hop asks PATH for `ssh`. `--help` stays local.
# The remote `main` receives the verb with the `qhost:` token removed.
# This does not open a real connection.

@testset "qhost hop" begin
    _with_fake_ssh() do log
        _main_capture(["qhost:HOST", "submit", "--help"])
        @test !isfile(log)
        code, _, _ = _main_capture(["qhost:example", "status"])
        @test code == 0
        argv = isfile(log) ? readlines(log) : String[]
        @test "example" in argv
        @test any(occursin("main([\"status\"])", a) for a in argv)
        @test !any(occursin("qhost:example", a) for a in argv)
    end
end
