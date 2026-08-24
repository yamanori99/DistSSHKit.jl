using Test

# Oracle: Pkg.develop(kit) then kit CLI `drive parent:2` prints SMOKE_OK.
# Does not cover host `drive.jl` without develop (local.jl).

@testset "Pkg.develop" begin
    fixture = _fixture("drive_local_smoke.jl")
    @test isfile(fixture)

    _mktemp_host() do proj
        _write_host_project!(proj, "SmokeAddApp")
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)

        _develop_kit!(proj)

        proc, combined = _run_kit_drive(; script=script, host_root=proj, local_workers=2)
        _assert_proc_ok(proc, combined; label="Pkg.develop drive")
        @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", combined)
    end
end
