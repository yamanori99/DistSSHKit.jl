using Test

# Oracle: child argv `SCRIPT.jl` (no `go`) is go, not unknown subcommand.
# Missing file fails with that message. Does not run slots. `bogus` / empty `go`
# live in unit (main exit 1, parse + go() usage).

@testset "go SCRIPT.jl shorthand" begin
    cmd = _kit_cli_cmd(["no_such_job.jl"])
    env = _child_julia_env(Dict("DISTSSHKIT_YES" => "1"))
    proc, out = _run_subprocess(setenv(cmd, env))
    @test proc.exitcode != 0
    @test !occursin("Unknown subcommand", out)
    @test occursin("script not found", out)
end
