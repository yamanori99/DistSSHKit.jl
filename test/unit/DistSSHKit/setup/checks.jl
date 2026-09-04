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

    @test DistSSHKit.juliaup_channel(v"1.12.6") == "1.12"
    @test DistSSHKit.juliaup_channel(VERSION) == "$(VERSION.major).$(VERSION.minor)"
    sh = DistSSHKit._juliaup_align_remote_sh("1.12")
    @test occursin(raw"$HOME/.juliaup/bin/juliaup", sh)
    @test occursin(" add ", sh) || occursin("add '", sh)
    @test occursin("update", sh) && occursin("default", sh)
    @test occursin("printf 'juliaup add %s failed", sh)
    # Channel must not enter remote diagnostics unquoted (shell metacharacters).
    sh_meta = DistSSHKit._juliaup_align_remote_sh("1.12\$(id)")
    @test occursin("'1.12\$(id)'", sh_meta)
    @test !occursin("juliaup add 1.12\$(id) failed", sh_meta)
    DistSSHKit.print_juliaup_align_fix!("user@host"; kind=:missing, channel="1.12")
    DistSSHKit.print_juliaup_align_fix!("user@host"; kind=:mismatch, channel="1.12")
    @test DistSSHKit.juliaup_controller_behind_channel(v"1.12.6", v"1.12.9")
    @test !DistSSHKit.juliaup_controller_behind_channel(v"1.12.9", v"1.12.6")
    @test !DistSSHKit.juliaup_controller_behind_channel(v"1.12.6", v"1.12.6")
    @test !DistSSHKit.juliaup_controller_behind_channel(v"1.12.6", v"1.11.9")
    @test DistSSHKit.print_juliaup_controller_patch_note!(
        v"1.12.9"; local_version=v"1.12.6", channel="1.12",
    )
    @test !DistSSHKit.print_juliaup_controller_patch_note!(
        v"1.12.6"; local_version=v"1.12.6", channel="1.12",
    )

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
