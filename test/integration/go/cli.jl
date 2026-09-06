using Test

# Oracle: child argv `SCRIPT.jl` (no command) does not infer `go`.
# Missing-file `go` lives in unit (parse + go() usage).

@testset "SCRIPT.jl without a command" begin
    cmd = _kit_cli_cmd(["no_such_job.jl"])
    env = _child_julia_env(Dict("DISTSSHKIT_YES" => "1"))
    proc, out = _run_subprocess(setenv(cmd, env))
    @test proc.exitcode != 0
    @test occursin("does not infer go / ride / drive", out)
    @test !occursin("script not found", out)
end
