using Test
using Pkg

@testset "setup checks" begin
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"1.12.6") == :none
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"1.12.9") == :patch
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"1.11.6") == :minor
    @test DistSSHKit.julia_version_mismatch_kind(v"1.12.6", v"2.0.6") == :minor
    # --check fails on :minor unless --ignore-julia-version (see check_prerequisites).
    @test DistSSHKit.julia_version_mismatch_kind(VERSION, VersionNumber(VERSION.major, VERSION.minor + 1, 0)) ==
        :minor

    r = withenv("PATH" => "/nonexistent-distsshkit-path") do
        redirect_stdout(devnull) do
            redirect_stderr(devnull) do
                DistSSHKit._report_local_host_tools!()
            end
        end
    end
    @test r.ssh == false
    @test r.rsync == false
    @test r.git == false

    expr = DistSSHKit._project_deps_probe_expr()
    @test occursin("locate_package", expr)
    @test occursin("not instantiated", expr)

    _with_tempdir() do dir
        @test DistSSHKit.probe_project_deps(dir) == "Project.toml not found"
        write(joinpath(dir, "Project.toml"), "[deps]\n")
        @test occursin("Manifest.toml not found", DistSSHKit.probe_project_deps(dir))
    end

    _with_tempdir() do dir
        write(joinpath(dir, "Project.toml"), "[deps]\n")
        Pkg.activate(dir) do
            Pkg.instantiate()
        end
        @test DistSSHKit.probe_project_deps(dir) === nothing
    end
end
