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
    @test DistSSHKit.remote_juliaup_candidates("Darwin") == [
        raw"$HOME/.juliaup/bin/juliaup",
        "/opt/homebrew/bin/juliaup",
        "/usr/local/bin/juliaup",
    ]
    @test DistSSHKit.remote_juliaup_candidates("Linux") == [raw"$HOME/.juliaup/bin/juliaup"]
    sh = DistSSHKit._juliaup_align_remote_sh("1.12")
    @test occursin(raw"$HOME/.juliaup/bin/juliaup", sh)
    @test occursin("/opt/homebrew/bin/juliaup", sh)
    @test occursin(" add ", sh) || occursin("add '", sh)
    @test occursin("update", sh) && occursin("default", sh)
    @test occursin("printf 'juliaup add %s failed", sh)
    # Channel must not enter remote diagnostics unquoted (shell metacharacters).
    sh_meta = DistSSHKit._juliaup_align_remote_sh("1.12\$(id)")
    @test occursin("'1.12\$(id)'", sh_meta)
    @test !occursin("juliaup add 1.12\$(id) failed", sh_meta)
    DistSSHKit.print_juliaup_align_fix!("user@host"; kind=:missing, channel="1.12")
    DistSSHKit.print_juliaup_align_fix!("user@host"; kind=:mismatch, channel="1.12")
    @test DistSSHKit.juliaup_parent_behind_channel(v"1.12.6", v"1.12.9")
    @test !DistSSHKit.juliaup_parent_behind_channel(v"1.12.9", v"1.12.6")
    @test !DistSSHKit.juliaup_parent_behind_channel(v"1.12.6", v"1.12.6")
    @test !DistSSHKit.juliaup_parent_behind_channel(v"1.12.6", v"1.11.9")
    @test DistSSHKit.print_juliaup_parent_patch_note!(
        v"1.12.9"; local_version=v"1.12.6", channel="1.12",
    )
    @test !DistSSHKit.print_juliaup_parent_patch_note!(
        v"1.12.6"; local_version=v"1.12.6", channel="1.12",
    )
    tip_out, _ = with_kit_verbosity(:verbose) do
        _capture_stdio() do _, _
            DistSSHKit.print_juliaup_parent_patch_note!(
                v"1.12.9"; local_version=v"1.12.6", channel="1.12",
            )
        end
    end
    @test occursin("setup --juliaup parent", tip_out)
    @test occursin(".juliaup", DistSSHKit.local_juliaup_candidates()[1])
    @test DistSSHKit.find_local_juliaup(String[]) === nothing
    mktempdir() do d
        ju = joinpath(d, "juliaup")
        jl = joinpath(d, "julia")
        write(ju, """
            #!/bin/sh
            case "\$1" in
              add|update|default) exit 0 ;;
              status) echo "1.12"; exit 0 ;;
              *) exit 1 ;;
            esac
            """)
        write(jl, """
            #!/bin/sh
            echo "julia version $(VERSION.major).$(VERSION.minor).$(VERSION.patch)"
            """)
        chmod(ju, 0o755)
        chmod(jl, 0o755)
        withenv("DISTSSHKIT_TEST_LOCAL_JULIAUP" => ju) do
            @test DistSSHKit.find_local_juliaup() == ju
            ver = DistSSHKit._juliaup_align_local!("$(VERSION.major).$(VERSION.minor)")
            @test DistSSHKit.julia_version_mismatch_kind(VERSION, ver) != :minor
        end
    end

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
