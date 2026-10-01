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
    @test occursin("echo already", sh)
    @test occursin("\$1==\"*\"", sh)
    up_sh = DistSSHKit._juliaup_update_remote_sh()
    @test occursin(raw"$HOME/.juliaup/bin/juliaup", up_sh)
    @test occursin("\"\$JU\" update", up_sh)
    @test !occursin("echo already", up_sh)
    @test !occursin("default", up_sh)
    st = """
    Default  Channel  Version
    -------------------------------------------------------------------------
         *  1.13     1.13.2+0.aarch64.apple.darwin14
          1.12     1.12.7+0.aarch64.apple.darwin14
    """
    @test DistSSHKit._juliaup_default_channel_from_status(st) == "1.13"
    @test DistSSHKit._juliaup_default_channel_from_status("no default here") === nothing
    # Channel must not enter remote diagnostics unquoted (shell metacharacters).
    sh_meta = DistSSHKit._juliaup_align_remote_sh("1.12\$(id)")
    @test occursin("'1.12\$(id)'", sh_meta)
    @test !occursin("juliaup add 1.12\$(id) failed", sh_meta)
    DistSSHKit.print_juliaup_align_fix!("user@host"; kind = :missing, channel = "1.12")
    DistSSHKit.print_juliaup_align_fix!("user@host"; kind = :mismatch, channel = "1.12")
    @test DistSSHKit.juliaup_parent_behind_channel(v"1.12.6", v"1.12.9")
    @test !DistSSHKit.juliaup_parent_behind_channel(v"1.12.9", v"1.12.6")
    @test !DistSSHKit.juliaup_parent_behind_channel(v"1.12.6", v"1.12.6")
    @test !DistSSHKit.juliaup_parent_behind_channel(v"1.12.6", v"1.11.9")
    @test DistSSHKit.print_juliaup_parent_patch_note!(
        v"1.12.9"; local_version = v"1.12.6", channel = "1.12",
    )
    @test !DistSSHKit.print_juliaup_parent_patch_note!(
        v"1.12.6"; local_version = v"1.12.6", channel = "1.12",
    )
    tip_out, _ = with_kit_verbosity(:verbose) do
        _capture_stdio() do _, _
            DistSSHKit.print_juliaup_parent_patch_note!(
                v"1.12.9"; local_version = v"1.12.6", channel = "1.12",
            )
        end
    end
    @test occursin("setup --juliaup parent", tip_out)
    @test occursin(".juliaup", DistSSHKit.local_juliaup_candidates()[1])
    @test DistSSHKit.find_local_juliaup(String[]) === nothing
    mktempdir() do d
        ju = joinpath(d, "juliaup")
        jl = joinpath(d, "julia")
        write(
            ju, """
            #!/bin/sh
            case "\$1" in
              add|update|default)
                echo "Checking for new Julia versions" >&2
                echo "'1.13' is already installed."
                exit 0
                ;;
              status) echo "1.12"; exit 0 ;;
              *) exit 1 ;;
            esac
            """
        )
        write(
            jl, """
            #!/bin/sh
            echo "julia version $(VERSION.major).$(VERSION.minor).$(VERSION.patch)"
            """
        )
        chmod(ju, 0o755)
        chmod(jl, 0o755)
        withenv("DISTSSHKIT_TEST_LOCAL_JULIAUP" => ju) do
            @test DistSSHKit.find_local_juliaup() == ju
            ch = "$(VERSION.major).$(VERSION.minor)"
            captured, r = _capture_stdio() do _, _
                DistSSHKit._juliaup_align_local!(ch)
            end
            @test r.changed
            @test DistSSHKit.julia_version_mismatch_kind(VERSION, r.ver) != :minor
            @test !occursin("Checking for new Julia versions", captured)
            @test !occursin("already installed", captured)
        end
    end

    mktempdir() do d
        ju = joinpath(d, "juliaup")
        jl = joinpath(d, "julia")
        ch = "$(VERSION.major).$(VERSION.minor)"
        write(
            ju,
            """
            #!/bin/sh
            case "\$1" in
              status) echo '       *  $ch     julia version'; exit 0 ;;
              add|update|default) echo "unexpected \$1" >&2; exit 1 ;;
              *) exit 1 ;;
            esac
            """,
        )
        write(
            jl,
            """
            #!/bin/sh
            echo "julia version $(VERSION.major).$(VERSION.minor).$(VERSION.patch)"
            """,
        )
        chmod(ju, 0o755)
        chmod(jl, 0o755)
        withenv("DISTSSHKIT_TEST_LOCAL_JULIAUP" => ju) do
            r = DistSSHKit._juliaup_align_local!(ch)
            @test !r.changed
            @test DistSSHKit.julia_version_mismatch_kind(VERSION, r.ver) != :minor
            out, _ = with_kit_verbosity(:progress) do
                _capture_stdio() do _, _
                    DistSSHKit.juliaup_align_remotes(["parent"]; confirm = false)
                end
            end
            @test occursin("parent: already on $ch", out)
        end
    end

    mktempdir() do d
        ju = joinpath(d, "juliaup")
        jl = joinpath(d, "julia")
        write(
            ju, """
            #!/bin/sh
            case "\$1" in
              add) echo "network failed"; exit 1 ;;
              status) echo "empty"; exit 0 ;;
              *) exit 1 ;;
            esac
            """
        )
        write(
            jl, """
            #!/bin/sh
            echo "julia version $(VERSION.major).$(VERSION.minor).$(VERSION.patch)"
            """
        )
        chmod(ju, 0o755)
        chmod(jl, 0o755)
        withenv("DISTSSHKIT_TEST_LOCAL_JULIAUP" => ju) do
            err = try
                DistSSHKit._juliaup_align_local!("$(VERSION.major).$(VERSION.minor)")
                nothing
            catch e
                sprint(showerror, e)
            end
            @test err !== nothing
            @test occursin("network failed", err)
        end
    end

    @test begin
        t = withenv("PATH" => "/nonexistent-distsshkit-path") do
            redirect_stdout(devnull) do
                redirect_stderr(devnull) do
                    DistSSHKit._report_local_host_tools!()
                end
            end
        end
        !t.ssh && !t.rsync && !t.git
    end

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
            Pkg.instantiate(; io = devnull)
        end
        @test DistSSHKit.probe_project_deps(dir) === nothing
    end

    @testset "check_prerequisites git commit missing is a warning" begin
        _with_tempdir() do dir
            write(joinpath(dir, "Project.toml"), "[deps]\n")
            out, result = with_kit_verbosity(:verbose) do
                _capture_stdio() do _, _
                    DistSSHKit.check_prerequisites(
                        String[], "auto", "~/App.jl", dir;
                        require_clean_git = false,
                    )
                end
            end
            @test occursin("Could not get local git commit", out)
            @test occursin("Skip hash check", out)
            @test !occursin("✗ Could not get local git commit", out)
            Sys.which("ssh") === nothing || @test result.ok
        end
    end

    @testset "check_prerequisites dirty tree" begin
        Sys.which("git") === nothing && return
        _with_tempdir() do dir
            write(joinpath(dir, "Project.toml"), "[deps]\n")
            run(pipeline(`git -C $dir init -q`; stdout = devnull, stderr = devnull))
            run(pipeline(`git -C $dir config user.email "test@example.com"`; stdout = devnull, stderr = devnull))
            run(pipeline(`git -C $dir config user.name "Test"`; stdout = devnull, stderr = devnull))
            run(pipeline(`git -C $dir add Project.toml`; stdout = devnull, stderr = devnull))
            run(pipeline(`git -C $dir commit -q -m init`; stdout = devnull, stderr = devnull))
            write(joinpath(dir, "dirty.txt"), "x\n")

            out_warn, result_warn = with_kit_verbosity(:verbose) do
                _capture_stdio() do _, _
                    DistSSHKit.check_prerequisites(
                        String[], "auto", "~/App.jl", dir;
                        require_clean_git = false,
                    )
                end
            end
            @test occursin("Git has uncommitted changes", out_warn)
            @test !occursin("✗ Git has uncommitted changes", out_warn)
            Sys.which("ssh") === nothing || @test result_warn.ok

            out_fail, result_fail = with_kit_verbosity(:verbose) do
                _capture_stdio() do _, _
                    DistSSHKit.check_prerequisites(
                        String[], "auto", "~/App.jl", dir;
                        require_clean_git = true,
                    )
                end
            end
            @test !result_fail.ok
            @test occursin("Git has uncommitted changes", out_fail)
        end
    end

    @testset "resolve_pkg_env follows Base.active_manifest" begin
        _with_tempdir() do root
            lab = joinpath(root, "lab")
            member = joinpath(lab, "experiments", "run1")
            mkpath(member)
            write(
                joinpath(lab, "Project.toml"), """
                name = "Lab"
                [workspace]
                projects = ["experiments/run1"]
                """
            )
            write(joinpath(lab, "Manifest.toml"), "# lock\n")
            write(
                joinpath(member, "Project.toml"), """
                name = "Run1"
                [deps]
                """
            )
            env = DistSSHKit.resolve_pkg_env(member)
            @test env.project_dir == DistSSHKit.canonical_local_path(member)
            @test env.env_dir == DistSSHKit.canonical_local_path(lab)
            @test env.manifest == DistSSHKit.canonical_local_path(joinpath(lab, "Manifest.toml"))
            @test DistSSHKit.julia_project_rel(env) == joinpath("experiments", "run1")
            shipped = DistSSHKit.ensure_manifest_ships!(member)
            @test shipped.env_dir == env.env_dir
            withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => nothing) do
                deploy = DistSSHKit.remote_deploy_root(member)
                julia_remote = DistSSHKit.resolve_remote_project_root(member)
                @test deploy == joinpath("~", basename(dirname(lab)), "lab")
                @test julia_remote == joinpath(deploy, "experiments", "run1")
                if Sys.which("git") !== nothing
                    run(pipeline(`git -C $lab init -q`; stdout = devnull, stderr = devnull))
                    @test DistSSHKit.remote_git_clone_dest(member) == deploy
                end
            end

            solo = joinpath(root, "solo")
            mkpath(solo)
            write(joinpath(solo, "Project.toml"), "name = \"Solo\"\n[deps]\n")
            bare = DistSSHKit.resolve_pkg_env(solo)
            @test bare.manifest === nothing
            @test bare.env_dir == bare.project_dir
            @test DistSSHKit.julia_project_rel(bare) == "."

            ver = joinpath(root, "ver")
            mkpath(ver)
            write(joinpath(ver, "Project.toml"), "name = \"Ver\"\n[deps]\n")
            write(joinpath(ver, "Manifest-v$(VERSION.major).$(VERSION.minor).toml"), "# v\n")
            versioned = DistSSHKit.resolve_pkg_env(ver)
            @test versioned.manifest == DistSSHKit.canonical_local_path(
                joinpath(ver, "Manifest-v$(VERSION.major).$(VERSION.minor).toml"),
            )
            @test versioned.env_dir == versioned.project_dir

            elsewhere = joinpath(root, "elsewhere")
            mkpath(elsewhere)
            outside_manifest = joinpath(root, "side", "Manifest.toml")
            mkpath(dirname(outside_manifest))
            write(outside_manifest, "# x\n")
            write(
                joinpath(elsewhere, "Project.toml"),
                "name = \"Out\"\nmanifest = \"$(outside_manifest)\"\n",
            )
            outside = DistSSHKit.resolve_pkg_env(elsewhere)
            @test outside.manifest == DistSSHKit.canonical_local_path(outside_manifest)
            @test_throws ArgumentError DistSSHKit.ensure_manifest_ships!(elsewhere)

            linked = joinpath(root, "linked")
            mkpath(linked)
            write(joinpath(linked, "Project.toml"), "name = \"Linked\"\n[deps]\n")
            write(joinpath(linked, "Manifest-real.toml"), "# in tree\n")
            symlink("Manifest-real.toml", joinpath(linked, "Manifest.toml"))
            linked_env = DistSSHKit.ensure_manifest_ships!(linked)
            @test linked_env.env_dir == DistSSHKit.canonical_local_path(linked)
            rm(joinpath(linked, "Manifest.toml"))
            symlink(outside_manifest, joinpath(linked, "Manifest.toml"))
            @test_throws ArgumentError DistSSHKit.ensure_manifest_ships!(linked)

            if Sys.which("git") !== nothing
                repo = joinpath(root, "repo")
                mkpath(repo)
                write(joinpath(repo, "Project.toml"), "name = \"Repo\"\nmanifest = \"$(outside_manifest)\"\n")
                run(pipeline(`git -C $repo init -q`; stdout = devnull, stderr = devnull))
                run(pipeline(`git -C $repo add Project.toml`; stdout = devnull, stderr = devnull))
                run(
                    pipeline(
                        `git -C $repo -c user.email=t@example.com -c user.name=t commit -q -m init`;
                        stdout = devnull,
                        stderr = devnull,
                    )
                )
                @test_throws ArgumentError DistSSHKit.ensure_manifest_in_git_worktree!(repo)

                held = joinpath(root, "held")
                mkpath(held)
                inside_lock = joinpath(held, "inside.toml")
                write(inside_lock, "# inside\n")
                ext = joinpath(root, "extlocks")
                mkpath(ext)
                ext_manifest = joinpath(ext, "Manifest.toml")
                symlink(inside_lock, ext_manifest)
                write(
                    joinpath(held, "Project.toml"),
                    "name = \"Held\"\nmanifest = \"$(ext_manifest)\"\n",
                )
                run(pipeline(`git -C $held init -q`; stdout = devnull, stderr = devnull))
                @test_throws ArgumentError DistSSHKit.ensure_manifest_in_git_worktree!(held)

                nest = joinpath(root, "nest")
                nest_member = joinpath(nest, "lab", "experiments", "run1")
                mkpath(nest_member)
                write(
                    joinpath(nest, "lab", "Project.toml"),
                    "name = \"NestLab\"\n[workspace]\nprojects = [\"experiments/run1\"]\n",
                )
                write(joinpath(nest, "lab", "Manifest.toml"), "# lock\n")
                write(joinpath(nest_member, "Project.toml"), "name = \"NestRun\"\n[deps]\n")
                run(pipeline(`git -C $nest init -q`; stdout = devnull, stderr = devnull))
                withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => nothing) do
                    nest_deploy = DistSSHKit.remote_deploy_root(nest_member)
                    @test DistSSHKit.remote_git_clone_dest(nest_member) == dirname(nest_deploy)
                    @test DistSSHKit.remote_delete_root(nest_member) == dirname(nest_deploy)
                    @test DistSSHKit.remote_delete_root(nest_member; cli_override = "/srv/job") == "/srv/job"
                    @test_throws ArgumentError DistSSHKit.remote_git_clone_dest(
                        nest_member; cli_override = "/srv/job",
                    )
                end
            end
        end
    end

    @testset "go cwd is the member project" begin
        member = "~/lab/experiments/run1"
        inner = DistSSHKit._go_remote_slot_shell_inner(
            member,
            "slot",
            "job.jl",
            String[],
            "julia",
        )
        @test occursin("experiments/run1", inner)
        @test occursin("--project=.", inner)
        @test !occursin("--project=experiments", inner)
    end
end
