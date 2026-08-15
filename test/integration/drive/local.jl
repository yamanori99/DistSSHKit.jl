using Test

# Oracle: host `src/cli/drive.jl` + `local:2` prints DISTSSHKIT_RUNNER_SMOKE_OK.
# Does not cover kit module CLI, --log-dir, or external host deps.

@testset "drive l:N" begin
    kit_root = _kit_root()
    fixture = _fixture("drive_local_smoke.jl")
    @test isfile(joinpath(kit_root, "src", "cli", "drive.jl"))
    @test isfile(fixture)

    _mktemp_host() do proj::String
        _write_host_project!(proj, "SmokeApp")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)

        proc, combined = _run_host_drive(; script=script, host_project=proj)
        _assert_proc_ok(proc, combined; label="drive l:N smoke")
        @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", combined)
    end
end
