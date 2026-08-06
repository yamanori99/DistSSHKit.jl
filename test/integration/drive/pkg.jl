using Test

@testset "drive l:N with external package" begin
    kit_root = _kit_root()
    fixture = _fixture("pkg_driver_smoke.jl")
    julia = _julia_exe()
    @test isfile(joinpath(kit_root, "src", "cli", "drive.jl"))
    @test isfile(fixture)

    _mktemp_host() do proj
        _write_host_project!(
            proj,
            "PkgDriverSmoke";
            uuid="11111111-1111-4111-8111-111111111111",
            extra_toml="""

            [deps]
            JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
            """,
        )
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force=true)

        _develop_kit!(proj; kit_root=kit_root, julia=julia)

        inst_cmd = setenv(`$julia --project=$proj -e 'using Pkg; Pkg.add("JSON3")'`, _child_julia_env())
        inst_proc, inst_out = _run_subprocess(inst_cmd)
        _assert_proc_ok(inst_proc, inst_out; label="Pkg.add JSON3")

        proc, combined = _run_host_drive(; julia=julia, script=script, host_project=proj)
        _assert_proc_ok(proc, combined; label="pkg driver smoke")
        @test occursin("PKG_DRIVER_SMOKE_OK nw=2", combined)
        @test occursin("Syncing driver to workers", combined)
    end
end
