using Test

# Oracle: staged with_kit recipes under a temp host — square_file CSV bytes,
# square_echo needle, pipeline_square CSV. Not SSH (test/e2e.jl).

@testset "with_kit drive local" begin
    kit_root = _kit_root()
    julia = _julia_exe()

    _mktemp_host() do tmp
        demos_dir = joinpath(tmp, "demos")
        mkpath(demos_dir)
        _stage_with_kit_demos!(demos_dir, kit_root)
        with_kit = joinpath(demos_dir, "with_kit")

        file_script = joinpath(with_kit, "square_file.jl")
        file_proc, file_out = _run_kit_drive(;
            julia=julia,
            kit_root=kit_root,
            script=file_script,
            script_args=["--n", "3"],
            host_root=tmp,
        )
        _assert_proc_ok(file_proc, file_out; label="square_file demo")
        @test occursin("Results:", file_out)

        file_csv = joinpath(with_kit, "output", "square_results.csv")
        @test isfile(file_csv)
        expected = join([
            "param,result",
            ("$n,$(n^2)" for n in 1:3)...,
        ], '\n') * '\n'
        @test read(file_csv, String) == expected
        @test occursin("wrote ", file_out)
        out_dir = joinpath(with_kit, "output")
        _assert_kit_progress_done(out_dir; kind=:drive)

        echo_script = joinpath(with_kit, "square_echo.jl")
        echo_proc, echo_out = _run_kit_drive(;
            julia=julia,
            kit_root=kit_root,
            script=echo_script,
            script_args=["--n", "3"],
            host_root=tmp,
        )
        _assert_proc_ok(echo_proc, echo_out; label="square_echo demo")
        @test occursin("param^2:", echo_out)
        _assert_kit_progress_done(out_dir; kind=:drive)

        pipe_script = joinpath(with_kit, "pipeline_square.jl")
        pipe_cmd = Cmd([julia, "--startup-file=no", "--project=$tmp", pipe_script, "--n", "3"])
        pipe_env = _child_julia_env(Dict(
            "DISTRIBUTED_INIT_DELAY_SEC" => "0",
            "DISTRIBUTED_PROJECT_ROOT" => tmp,
        ))
        pipe_proc, pipe_out = _run_subprocess(setenv(pipe_cmd, pipe_env))
        _assert_proc_ok(pipe_proc, pipe_out; label="pipeline_square demo")
        @test occursin("pipeline! ok", pipe_out)
        pipe_csv = joinpath(with_kit, "output", "square_results.csv")
        @test isfile(pipe_csv)
        @test read(pipe_csv, String) == expected
        _assert_kit_progress_done(out_dir; kind=:drive)
    end
end
