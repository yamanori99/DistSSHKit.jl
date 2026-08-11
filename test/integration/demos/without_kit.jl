using Test

@testset "without_kit go local" begin
    kit_root = _kit_root()
    julia = _julia_exe()
    # Drop Pkg.test's JULIA_LOAD_PATH so stdlibs (Random) resolve under --project=.
    env = _child_julia_env()

    for (name, args) in (("pi_file.jl", ["4"]), ("pi_echo.jl", ["4"]))
        script = joinpath(kit_root, "demos", "without_kit", name)
        @test isfile(script)

        proc_solo = run(
            pipeline(
                setenv(Cmd(vcat([julia, "--project=$(kit_root)", script], args)), env);
                stdout=devnull,
                stderr=stderr,
            );
            wait=true,
        )
        @test proc_solo.exitcode == 0

        proc_go = run(
            pipeline(
                setenv(
                    Cmd(vcat([
                        julia,
                        "--project=$(kit_root)",
                        "-m",
                        "DistSSHKit",
                        "go",
                        "-q",
                        "-y",
                        script,
                    ], args)),
                    env,
                );
                stdout=devnull,
                stderr=stderr,
            );
            wait=true,
        )
        @test proc_go.exitcode == 0
    end

    pipe_script = joinpath(kit_root, "demos", "without_kit", "pipeline_pi.jl")
    @test isfile(pipe_script)
    pipe_cmd = Cmd([julia, "--startup-file=no", "--project=$(kit_root)", pipe_script, "4"])
    pipe_proc, pipe_out = _run_subprocess(setenv(pipe_cmd, env))
    _assert_proc_ok(pipe_proc, pipe_out; label="pipeline_pi demo")
    @test occursin("pipeline ok", pipe_out)
end
