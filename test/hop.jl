# A client `qhost:` hop asks PATH for `ssh`. `--help` stays local.
# The remote `-e` names DistSSHQueue as the fallback and DistSSHKit when that
# project depends on it. This does not open a real connection.

@testset "qhost hop" begin
    _with_fake_ssh() do log
        _main_capture(["qhost:HOST", "submit", "--help"])
        @test !isfile(log)
        _main_capture(["qhost:example", "status"])
        argv = isfile(log) ? readlines(log) : String[]
        @test "example" in argv
        @test any(occursin("haskey(deps, \"DistSSHKit\")", a) for a in argv)
    end
end
