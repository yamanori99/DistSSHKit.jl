using Test

@testset "drive log via kit module CLI" begin
    fixture = _fixture("drive_local_smoke.jl")
    julia = _julia_exe()

    _mktemp_host() do proj
        _write_host_project!(proj, "SmokeLogAddApp")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        log_dir = joinpath(proj, "logs")
        mkpath(log_dir)

        _develop_kit!(proj; julia=julia)

        cmd = _kit_cli_cmd(
            ["drive", "local:2", "--log-dir", log_dir, script];
            julia=julia,
            project=proj,
        )
        _assert_drive_log_output(;
            cmd=setenv(
                cmd,
                _child_julia_env(Dict(
                    "DISTRIBUTED_INIT_DELAY_SEC" => "0",
                    "DISTRIBUTED_PROJECT_ROOT" => proj,
                )),
            ),
            log_dir=log_dir,
        )
    end
end
