using Test

# Oracle: `src/cli/drive.jl` + `--log-dir` writes one log with SMOKE_OK.
# Does not cover `-m DistSSHKit` (log_via_module.jl).

@testset "drive log via script path" begin
    fixture = _fixture("drive_local_smoke.jl")
    julia = _julia_exe()

    _mktemp_host() do proj
        _write_host_project!(proj, "SmokeLogApp")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)
        log_dir = joinpath(proj, "logs")
        mkpath(log_dir)

        drive = joinpath(_kit_root(), "src", "cli", "drive.jl")
        cmd = `$julia --project=$proj $drive parenthost:2 --log-dir $log_dir $script`
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
