using Test

# Oracle: child `julia -m DistSSHKit <cmd> --help` / `--version` exits 0 and
# prints a Usage / version needle. Does not run workers, SSH, or rsync.

@testset "CLI child help and version" begin
    env = _child_julia_env(Dict("DISTSSHKIT_YES" => "1"))
    for cmd in ("drive", "go", "setup", "size")
        proc, out = _run_subprocess(setenv(_kit_cli_cmd([cmd, "--help"]), env))
        @test proc.exitcode == 0
        @test occursin("Usage", out)
        @test occursin(cmd, lowercase(out))
        @test !occursin("Unknown subcommand", out)

        proc, out = _run_subprocess(setenv(_kit_cli_cmd([cmd, "--version"]), env))
        @test proc.exitcode == 0
        @test occursin("DistSSHKit $(DistSSHKit.dist_ssh_kit_version())", out)
    end

    proc, out = _run_subprocess(setenv(_kit_cli_cmd([
        "drive", "--mem-headroom", "0.5", "--parent-gb", "0.2", "--help",
    ]), env))
    @test proc.exitcode == 0
    @test occursin("Usage", out)
    @test occursin("--mem-headroom", out)
    @test occursin("--parent-gb", out)

    proc, out = _run_subprocess(setenv(_kit_cli_cmd([
        "go", "--julia", "/opt/julia/bin/julia", "--output-dir", "my_runs", "--help",
    ]), env))
    @test proc.exitcode == 0
    @test occursin("Usage", out)
    @test occursin("--julia", out)
    @test occursin("--output-dir", out)
end
