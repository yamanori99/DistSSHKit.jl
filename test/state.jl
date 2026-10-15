# CLI entry and env do not leak across `main` calls.

@testset "cli state" begin
    _main_capture(["--help"])
    code, out, err = _stdio_capture(() -> DistSSHQueue.main(["--help"]))
    @test code == 0
    @test occursin("DistSSHQueue", out)
    @test !occursin("julia -m DistSSHKit", out * err)
    first = _main_capture(["--help"])
    second = _main_capture(["--help"])
    @test first == second
    # Direct call is inlined into this testset and JET then looks up `DistSSHRun` here.
    # A direct call is inlined into this testset, and JET then requires
    # `DistSSHRun` as a global here. `getfield` keeps that body in DistSSHKit.
    # The same pass rejects `Main.DistSSHRun` written in this file, so the
    # comparison is a string.
    bind = getfield(DistSSHKit, Symbol("_bind_run_in_main!"))
    @test (bind(); bind(); true)
    @test eval(Meta.parse("Main.DistSSHRun === DistSSHRun"))
end
