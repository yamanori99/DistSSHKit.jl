using Test

# Oracle: host `drive.jl` + `local:2` exits non-zero when the driver throws.
# Happy path is `local.jl`. Not SSH.

@testset "drive l:N driver error" begin
    _mktemp_host() do proj
        _write_host_project!(proj, "FailApp")
        script = joinpath(proj, "job.jl")
        write(script, "error(\"DISTSSHKIT_RUNNER_BOOM\")\n")
        proc, combined = _run_host_drive(; script=script, host_project=proj)
        @test proc.exitcode != 0
        @test occursin("DISTSSHKIT_RUNNER_BOOM", combined)
    end
end
