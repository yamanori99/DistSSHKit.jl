if !isdefined(Main, :_run_kit_setup)

"""Run the kit `setup` CLI as a subprocess (for CLI exit-code tests).

Kit logs land under `<project>/.distsshkit/setup/`. When `project_root` is
omitted, use an ephemeral host so unit tests never write into the kit checkout.
SSH E2E passes an explicit durable host under `test/artifacts/ssh-e2e/`.
"""
function _run_kit_setup(;
    setup_args::Vector{String},
    kit_root::String=_kit_root(),
    julia::String=_julia_exe(),
    project_root=nothing,
    extra_env::Dict{String,String}=Dict{String,String}(),
)
    function _run(proj)
        cmd = _kit_cli_cmd(vcat(["setup"], setup_args); julia=julia, project=kit_root)
        base = Dict{String,String}(
            "DISTSSHKIT_YES" => "1",
            "DISTRIBUTED_PROJECT_ROOT" => proj,
        )
        env = _child_julia_env(merge(base, extra_env))
        return _run_subprocess(setenv(cmd, env))
    end
    if project_root !== nothing
        return _run(abspath(string(project_root)))
    end
    return _with_tempdir() do proj
        _write_host_project!(proj, "SetupCliHost")
        return _run(proj)
    end
end

function _fake_setup_remote_env(state_dir)::Dict{String,String}
    return Dict{String,String}(
        "DISTSSHKIT_TEST_SSH" => _fixture("fake_setup_ssh.jl"),
        "DISTSSHKIT_TEST_RSYNC" => _fixture("fake_setup_rsync.sh"),
        "DISTSSHKIT_TEST_STATE_ROOT" => abspath(string(state_dir)),
        "DISTSSHKIT_YES" => "1",
    )
end

"""Apply a quiet+yes kit CLI session."""
function _apply_quiet_setup_session!()
    DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=true, yes=true))
    return nothing
end

"""Redirect stdin/stdout to temp files; return `(captured_stdout, f's return value)`.

Use only when asserting on printed messages. For return-value checks, prefer
`_apply_quiet_setup_session!` / `report=false` instead of discarding stdout.
"""
function _capture_stdio(f::Function)
    mktemp() do _stdin_path, stdin_io
        mktemp() do stdout_path, stdout_io
            value = redirect_stdout(stdout_io) do
                redirect_stdin(stdin_io) do
                    f(stdin_io, stdout_io)
                end
            end
            flush(stdout_io)
            return read(stdout_path, String), value
        end
    end
end

"""Run `f` with kit verbosity `v`, then restore the previous value.

Use this whenever a test asserts on captured kit stdout. `Pkg.test()` pins
`:progress` (TTY CLI default); do not assume the module-load `:verbose`.
"""
function with_kit_verbosity(f, v::Symbol)
    prev = DistSSHKit.kit_verbosity()
    try
        DistSSHKit.set_kit_verbosity!(v)
        return f()
    finally
        DistSSHKit.close_log_file()
        DistSSHKit.kit_progress_done!()
        DistSSHKit._set_kit_progress_sidecar!(nothing)
        DistSSHKit.set_kit_verbosity!(prev)
    end
end

"""Run the kit `go` CLI as a subprocess.

Same project-root rule as [`_run_kit_setup`](@ref): omit `project_root` only for
ephemeral unit hosts; SSH E2E passes a kept host explicitly.
"""
function _run_kit_go(;
    script::AbstractString,
    hosts::Vector{String}=String[],
    script_args::Vector{String}=String[],
    kit_root::String=_kit_root(),
    julia::String=_julia_exe(),
    project_root=nothing,
    go_flags::Vector{String}=String[],
    extra_env::Dict{String,String}=Dict{String,String}(),
)
    function _run(proj)
        cmd = _kit_cli_cmd(
            vcat(["go"], go_flags, hosts, [String(script)], script_args);
            julia=julia,
            project=kit_root,
        )
        base = Dict{String,String}(
            "DISTSSHKIT_YES" => "1",
            "DISTRIBUTED_PROJECT_ROOT" => proj,
        )
        env = _child_julia_env(merge(base, extra_env))
        return _run_subprocess(setenv(cmd, env))
    end
    if project_root !== nothing
        return _run(abspath(string(project_root)))
    end
    return _with_tempdir() do proj
        _write_host_project!(proj, "GoCliHost")
        return _run(proj)
    end
end

"""Run the kit `size` CLI as a subprocess.

Same project-root rule as [`_run_kit_setup`](@ref).
"""
function _run_kit_size(;
    size_args::Vector{String},
    kit_root::String=_kit_root(),
    julia::String=_julia_exe(),
    project_root=nothing,
    extra_env::Dict{String,String}=Dict{String,String}(),
)
    function _run(proj)
        cmd = _kit_cli_cmd(vcat(["size"], size_args); julia=julia, project=kit_root)
        base = Dict{String,String}(
            "DISTSSHKIT_YES" => "1",
            "DISTRIBUTED_PROJECT_ROOT" => proj,
        )
        env = _child_julia_env(merge(base, extra_env))
        return _run_subprocess(setenv(cmd, env))
    end
    if project_root !== nothing
        return _run(abspath(string(project_root)))
    end
    return _with_tempdir() do proj
        _write_host_project!(proj, "SizeCliHost")
        return _run(proj)
    end
end

end
