using Test

# Oracle: host project with JSON + `drive.jl` subprocess prints PKG_DRIVER_SMOKE_OK.
# Does not cover kit CLI after Pkg.develop (pkg_develop.jl).

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
            uuid = "11111111-1111-4111-8111-111111111111",
            extra_toml = """

            [deps]
            JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
            """,
        )
        script = joinpath(proj, "job.jl")
        cp(fixture, script; force = true)

        _develop_kit!(proj; kit_root = kit_root, julia = julia)

        inst_cmd = setenv(`$julia --project=$proj -e 'using Pkg; Pkg.add("JSON")'`, _child_julia_env())
        inst_proc, inst_out = _run_subprocess(inst_cmd)
        _assert_proc_ok(inst_proc, inst_out; label = "Pkg.add JSON")

        proc, combined = _run_host_drive(; julia = julia, script = script, host_project = proj)
        _assert_proc_ok(proc, combined; label = "pkg driver smoke")
        @test occursin("PKG_DRIVER_SMOKE_OK nw=2", combined)
        @test occursin("Syncing driver to workers", combined)
    end
end
