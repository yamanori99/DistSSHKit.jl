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
end
