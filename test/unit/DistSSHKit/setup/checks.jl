using Test

@testset "setup checks" begin
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"1.12.6") == :none
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"1.12.9") == :patch
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"1.11.6") == :minor
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"2.0.6") == :minor

    expr = DistSSHKit._project_deps_probe_expr()
    @test occursin("locate_package", expr)
    @test occursin("not instantiated", expr)

    mktempdir() do dir
        @test DistSSHKit.probe_project_deps(dir) == "Project.toml not found"
        write(joinpath(dir, "Project.toml"), "[deps]\n")
        @test occursin("Manifest.toml not found", DistSSHKit.probe_project_deps(dir))
    end

    # Repo root: test/unit/DistSSHKit/setup → four parents up.
    repo = dirname(dirname(dirname(dirname(@__DIR__))))
    @test DistSSHKit.probe_project_deps(repo) === nothing
end
