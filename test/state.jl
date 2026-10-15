# CLI entry and env do not leak across `main` calls.

@testset "cli state" begin
    _main_capture(["--help"])
    code, out, err = _stdio_capture(() -> DistSSHQueue.main(["--help"]))
    @test code == 0
    @test occursin("DistSSHQueue", out)
    @test !occursin("julia -m DistSSHKit", out * err)
    saved_env = copy(ENV)
    saved_args = copy(ARGS)
    cold = _main_capture(["go", "--help"])
    @test ENV == saved_env
    @test ARGS == saved_args
    warm = _main_capture(["go", "--help"])
    @test cold == warm
    @test ENV == saved_env
    @test ARGS == saved_args
    # A direct call is inlined into this testset, and JET then looks up
    # `DistSSHRun` here. `getfield` keeps that body in DistSSHKit.
    # This process already `using DistSSHRun`, so the branch that creates the
    # binding runs only in subprocess.jl.
    bind = getfield(DistSSHKit, Symbol("_bind_run_in_main!"))
    @test (bind(); bind(); true)
    # `getglobal(Main, :DistSSHRun)` is the same JET warning as writing the
    # name here, so the comparison stays a parsed string.
    @test eval(Meta.parse("Main.DistSSHRun === DistSSHRun"))
end
