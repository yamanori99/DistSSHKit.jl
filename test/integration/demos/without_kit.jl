using Test

# Oracle: solo julia and kit `go` agree on π (echo line / `pi_results.txt`).

@testset "without_kit go local" begin
    kit_root = _kit_root()
    julia = _julia_exe()
    echo = joinpath(kit_root, "demos", "without_kit", "pi_echo.jl")
    file = joinpath(kit_root, "demos", "without_kit", "pi_file.jl")
    pipe_script = joinpath(kit_root, "demos", "without_kit", "pipeline_pi.jl")
    env = _child_julia_env()

    _with_tempdir() do tmp
        solo_echo_proc, solo_echo_out = _run_subprocess(setenv(
            Cmd([julia, "--startup-file=no", "--project=$kit_root", echo, "4"]),
            env,
        ))
        _assert_proc_ok(solo_echo_proc, solo_echo_out; label="pi_echo solo")
        echo_line = match(r"π ≈ .+", solo_echo_out)
        @test echo_line !== nothing

        go_echo_proc, go_echo_out = _run_kit_go(;
            script=echo,
            script_args=["4"],
            project_root=tmp,
            go_flags=["-y"],
        )
        _assert_proc_ok(go_echo_proc, go_echo_out; label="pi_echo go")
        @test occursin(echo_line.match, go_echo_out)

        solo_dir = joinpath(tmp, "solo_out")
        mkpath(solo_dir)
        solo_file_proc, solo_file_out = _run_subprocess(setenv(
            Cmd([julia, "--startup-file=no", "--project=$kit_root", file, "4"]),
            _child_julia_env(Dict("DISTRIBUTED_OUTPUT_DIR" => solo_dir)),
        ))
        _assert_proc_ok(solo_file_proc, solo_file_out; label="pi_file solo")
        solo_body = read(joinpath(solo_dir, "pi_results.txt"), String)
        @test occursin("pi=", solo_body)

        go_file_proc, go_file_out = _run_kit_go(;
            script=file,
            script_args=["4"],
            project_root=tmp,
            go_flags=["-y"],
        )
        _assert_proc_ok(go_file_proc, go_file_out; label="pi_file go")
        file_batch = _ssh_e2e_latest_go_batch(tmp)
        @test file_batch !== nothing
        file_batch === nothing && error("expected go batch for pi_file")
        @test read(joinpath(file_batch, "local", "pi_results.txt"), String) == solo_body

        pipe_proc, pipe_out = _run_subprocess(setenv(
            Cmd(Cmd([julia, "--startup-file=no", "--project=$kit_root", pipe_script, "4"]); dir=tmp),
            env,
        ))
        _assert_proc_ok(pipe_proc, pipe_out; label="pipeline_pi demo")
        @test occursin("pipeline ok", pipe_out)
        pipe_batch = _ssh_e2e_latest_go_batch(tmp)
        @test pipe_batch !== nothing
        pipe_batch === nothing && error("expected go batch for pipeline_pi")
        a = read(joinpath(pipe_batch, "local-1", "pi_results.txt"), String)
        b = read(joinpath(pipe_batch, "local-2", "pi_results.txt"), String)
        @test occursin("pi=", a)
        @test a == b
    end
end
