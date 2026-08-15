#!/usr/bin/env julia
# Real-SSH E2E against testenv/docker-ssh workers. Not part of Pkg.test().
# Oracle: OpenSSH + rsync + remote Julia (setup / drive / go / git). Local
# with_kit recipes are test/integration/demos/with_kit.jl — not duplicated here.
#
#   testenv/docker-ssh/scripts/up.sh --e2e
#   DISTSSHKIT_SSH_E2E=1 julia --project=. test/e2e.jl   # from kit root
#
# Afterward open only:
#   $(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt

using Test
using DistSSHKit

kit_root = abspath(joinpath(@__DIR__, ".."))
include(joinpath(kit_root, "test", "support.jl"))

if !_ssh_e2e_enabled()
    @info "Skipping SSH E2E (set DISTSSHKIT_SSH_E2E=1 to enable)"
    exit(0)
end

g = _docker_ssh_generated()
if !isfile(g.ssh_config) || !isfile(g.hosts_file)
    error("docker-ssh not ready: missing $(g.ssh_config). Run testenv/docker-ssh/scripts/up.sh")
end

hosts = collect(String, _ssh_e2e_hosts())
remote_root = _ssh_e2e_remote_root()
e2e_env = _ssh_e2e_env(; remote_project=remote_root)
remote_tokens = ["$(hosts[1]):1", "$(hosts[2]):1"]

@testset "SSH E2E (docker-ssh)" verbose=true begin
    _with_ssh_e2e_suite() do suite
        @testset "julia path resolve (controller + remotes)" begin
            withenv(e2e_env...) do
                ctrl = DistSSHKit.resolve_controller_julia("auto")
                @test isabspath(ctrl)
                @test isfile(ctrl)
                @test ctrl != "julia"
                ctrl_ver = DistSSHKit.parse_julia_version(read(`$ctrl --version`, String))
                @test ctrl_ver isa VersionNumber
                os_label = Sys.isapple() ? "darwin" : (Sys.islinux() ? "linux" : Sys.KERNEL)
                _ssh_e2e_record_julia!(suite, "controller($(os_label))", ctrl, string(ctrl_ver))
                _assert_ssh_e2e_api_ok(suite, "controller_julia", true, "path=$(ctrl) ver=$(ctrl_ver)")

                for host in hosts
                    found = DistSSHKit.resolve_remote_julia(host, "auto")
                    @test found isa AbstractString
                    found = found::String
                    @test isabspath(found) || startswith(found, '/')
                    @test found != "julia"
                    ver = DistSSHKit.get_remote_julia_version(host, found)
                    @test ver isa VersionNumber
                    @test ver.major == ctrl_ver.major
                    @test ver.minor == ctrl_ver.minor
                    _ssh_e2e_record_julia!(suite, "remote($(host))", found, string(ver))
                    _assert_ssh_e2e_api_ok(
                        suite,
                        "remote_julia_$(host)",
                        true,
                        "path=$(found) ver=$(ver)",
                    )
                end
            end
        end

        # Remote suite (both docker workers). Local with_kit demos live in
        # test/integration/demos/with_kit.jl — not duplicated here.
        proj = suite.project_remote
        _stage_ssh_e2e_remote_host!(proj; kit_root=kit_root)
        smoke = joinpath(proj, "smoke.jl")
        echo_script = joinpath(proj, "demos", "with_kit", "square_echo.jl")
        pi_echo = joinpath(proj, "demos", "without_kit", "pi_echo.jl")
        pi_file = joinpath(proj, "demos", "without_kit", "pi_file.jl")

        @testset "setup --delete (clean slate)" begin
            proc, out = _run_kit_setup(;
                setup_args=["--delete", "--remote-path", remote_root, hosts...],
                project_root=proj,
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "setup_delete", proc, out; project=proj, kit=:setup)
        end

        @testset "setup --rsync" begin
            proc, out = _run_kit_setup(;
                setup_args=["--rsync", "--remote-path", remote_root, hosts...],
                project_root=proj,
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "setup_rsync", proc, out; project=proj, kit=:setup)
            for host in hosts
                p, ssh_out = _run_subprocess(Cmd([
                    "ssh", "-F", g.ssh_config, host,
                    "test -f $(remote_root)/Project.toml",
                ]))
                _assert_proc_ok(p, ssh_out; label="rsync $(host) Project.toml")
            end
        end

        @testset "setup --instantiate" begin
            proc, out = _run_kit_setup(;
                setup_args=["--instantiate", "--remote-path", remote_root, hosts...],
                project_root=proj,
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "setup_instantiate", proc, out; project=proj, kit=:setup)
        end

        @testset "setup --check (major.minor; no --ignore-julia-version)" begin
            # rsync excludes .git/; --check warns on missing remote hash but must
            # still pass Julia major.minor + project/deps. Git parity is not
            # claimed for the rsync path (see docker-ssh README).
            proc, out = _run_kit_setup(;
                setup_args=["--check", "--remote-path", remote_root, hosts...],
                project_root=proj,
                extra_env=merge(e2e_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "setup_check", proc, out; project=proj, kit=:setup)
            @test occursin("Julia", out)
        end

        @testset "size two remotes" begin
            proc, out = _run_kit_size(;
                size_args=["-q", hosts...],
                project_root=proj,
                extra_env=merge(e2e_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "size_remotes", proc, out)
            @test occursin(hosts[1], out)
            @test occursin(hosts[2], out)
        end

        @testset "drive square_echo two remotes" begin
            proc, out = _run_kit_drive(;
                script=echo_script,
                host_root=proj,
                local_workers=0,
                remote_hosts=remote_tokens,
                script_args=["4"],
                drive_flags=["-y", "-q"],
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "drive_square_echo", proc, out)
            @test occursin("param^2:", out)
        end

        @testset "drive mixed local+remotes smoke" begin
            proc, out = _run_kit_drive(;
                script=smoke,
                host_root=proj,
                local_workers=1,
                remote_hosts=remote_tokens,
                drive_flags=["-y", "-q"],
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "drive_mixed", proc, out)
            @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=3", out)
        end

        @testset "go pi_echo both remotes" begin
            proc, out = _run_kit_go(;
                script=pi_echo,
                hosts=remote_tokens,
                script_args=["32"],
                project_root=proj,
                go_flags=["-y"],
                extra_env=merge(e2e_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "go_pi_echo", proc, out; project=proj, kit=:go)
            @test occursin(hosts[1], out)
            @test occursin(hosts[2], out)
            @test count(r"π ≈", out) >= 2
        end

        @testset "go pi_file both remotes + collect" begin
            proc, out = _run_kit_go(;
                script=pi_file,
                hosts=remote_tokens,
                script_args=["32"],
                project_root=proj,
                go_flags=["-y"],
                extra_env=merge(e2e_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "go_pi_file", proc, out; project=proj, kit=:go)
            batch = _ssh_e2e_latest_go_batch(proj)
            @test batch !== nothing
            for host in hosts
                slot = joinpath(batch::String, host)
                @test isdir(slot)
                @test isfile(joinpath(slot, "pi_results.txt"))
                body = read(joinpath(slot, "pi_results.txt"), String)
                @test occursin("pi=", body)
            end
        end

        # Path boundary: `~/…` remote root must still collect absolute find paths.
        @testset "drive square_file collect with tilde remote root" begin
            tilde_root = _ssh_e2e_tilde_remote_root()
            tilde_env = _ssh_e2e_env(; remote_project=tilde_root)
            square_file = joinpath(proj, "demos", "with_kit", "square_file.jl")
            out_csv = joinpath(proj, "demos", "with_kit", "output", "square_results.csv")
            isfile(out_csv) && rm(out_csv)

            proc, out = _run_kit_setup(;
                setup_args=["--delete", "--remote-path", tilde_root, hosts...],
                project_root=proj,
                extra_env=tilde_env,
            )
            _assert_ssh_e2e_ok(suite, "tilde_delete", proc, out; project=proj, kit=:setup)

            proc, out = _run_kit_setup(;
                setup_args=["--rsync", "--remote-path", tilde_root, hosts...],
                project_root=proj,
                extra_env=tilde_env,
            )
            _assert_ssh_e2e_ok(suite, "tilde_rsync", proc, out; project=proj, kit=:setup)

            proc, out = _run_kit_setup(;
                setup_args=["--instantiate", "--remote-path", tilde_root, hosts...],
                project_root=proj,
                extra_env=tilde_env,
            )
            _assert_ssh_e2e_ok(suite, "tilde_instantiate", proc, out; project=proj, kit=:setup)

            proc, out = _run_kit_drive(;
                script=square_file,
                host_root=proj,
                local_workers=0,
                remote_hosts=remote_tokens,
                script_args=["4"],
                drive_flags=["-y", "-q"],
                extra_env=tilde_env,
            )
            _assert_ssh_e2e_ok(suite, "tilde_drive_square_file", proc, out)
            @test isfile(out_csv)
            @test occursin("param,result", read(out_csv, String))
        end

        # Julian API path (same remotes): setup! → go! / pipeline!
        @testset "Julian API setup! + go!/pipeline!" begin
            withenv(e2e_env...) do
                session = KitSession(
                    project=proj,
                    workers=hosts,
                    remote=remote_root,
                    yes=true,
                    quiet=true,
                )
                prep = setup!(session, :delete, :rsync, :instantiate)
                _assert_ssh_e2e_api_ok(
                    suite,
                    "api_setup",
                    prep.ok,
                    "hosts=$(length(prep.hosts))",
                )
                @test prep.ok
                @test !prep.cancelled
                @test length(prep.hosts) == length(hosts)
                @test all(h -> h.ok, prep.hosts)

                go_res = go!(
                    pi_file,
                    remote_tokens[1];
                    project=proj,
                    remote=remote_root,
                    args=["16"],
                    yes=true,
                    quiet=true,
                    julia="auto",
                )
                _assert_ssh_e2e_api_ok(suite, "api_go", go_res.ok)
                @test go_res.ok
                go_txt = joinpath(go_res.output_dir, hosts[1], "pi_results.txt")
                @test isfile(go_txt)
                @test occursin("pi=", read(go_txt, String))

                pipe_res = pipeline!(
                    echo_script,
                    remote_tokens[2];
                    project=proj,
                    remote=remote_root,
                    args=["3"],
                    collect=false,
                    enable_log=false,
                    yes=true,
                    quiet=true,
                    julia="auto",
                )
                _assert_ssh_e2e_api_ok(suite, "api_pipeline", pipe_res.ok)
                @test pipe_res.ok
            end
        end

        @testset "setup --rsync refuses nonempty" begin
            proc, out = _run_kit_setup(;
                setup_args=["--rsync", "--remote-path", remote_root, hosts[1]],
                project_root=proj,
                extra_env=merge(e2e_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _ssh_e2e_record!(suite, "setup_rsync_refuse", proc, out; expect_ok=false, project=proj, kit=:setup)
            @test proc.exitcode != 0
            @test occursin("refusing", lowercase(out))
        end

        @testset "inter-worker SSH (w1 → w2 via compose DNS)" begin
            cmd = Cmd([
                "ssh", "-F", g.ssh_config, hosts[1],
                "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 " *
                "dev@worker-2 'echo inter-ok'",
            ])
            proc, out = _run_subprocess(cmd)
            _assert_ssh_e2e_ok(suite, "inter_worker_ssh", proc, out)
            @test occursin("inter-ok", out)
        end

        # Git path (separate remote root): bare on w1 → clone → check hash → sync → --require-git.
        @testset "git clone + sync + require-git" begin
            git_root = _ssh_e2e_git_remote_root()
            git_env = _ssh_e2e_env(; remote_project=git_root)
            seed = nothing
            withenv(git_env...) do
                seed = _ssh_e2e_seed_git_origin!(proj)
            end
            @test seed !== nothing
            seed = seed::NamedTuple

            proc, out = _run_kit_setup(;
                setup_args=[
                    "--delete", "--remote-path", git_root, hosts...,
                ],
                project_root=proj,
                extra_env=git_env,
            )
            _assert_ssh_e2e_ok(suite, "git_delete", proc, out; project=proj, kit=:setup)

            proc, out = _run_kit_setup(;
                setup_args=[
                    "--clone",
                    "--repo", seed.origin_workers,
                    "--remote-path", git_root,
                    hosts...,
                ],
                project_root=proj,
                extra_env=git_env,
            )
            _assert_ssh_e2e_ok(suite, "git_clone", proc, out; project=proj, kit=:setup)

            proc, out = _run_kit_setup(;
                setup_args=[
                    "--instantiate", "--remote-path", git_root, hosts...,
                ],
                project_root=proj,
                extra_env=git_env,
            )
            _assert_ssh_e2e_ok(suite, "git_instantiate", proc, out; project=proj, kit=:setup)

            proc, out = _run_kit_setup(;
                setup_args=["--check", "--remote-path", git_root, hosts...],
                project_root=proj,
                extra_env=merge(git_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "git_check", proc, out; project=proj, kit=:setup)
            local_before = DistSSHKit.get_local_git_hash(proj; short=12)
            @test local_before isa String
            @test occursin(local_before::String, out)

            bumped = nothing
            withenv(git_env...) do
                bumped = _ssh_e2e_git_bump_commit!(proj)
            end
            @test bumped isa String
            @test bumped != local_before

            proc, out = _run_kit_setup(;
                setup_args=["--sync", "--remote-path", git_root, hosts...],
                project_root=proj,
                extra_env=merge(git_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "git_sync", proc, out; project=proj, kit=:setup)

            proc, out = _run_kit_setup(;
                setup_args=["--check", "--remote-path", git_root, hosts...],
                project_root=proj,
                extra_env=merge(git_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "git_check_after_sync", proc, out; project=proj, kit=:setup)
            @test occursin(bumped::String, out)

            # drive --require-git must pass when remotes have matching .git/
            proc, out = _run_kit_drive(;
                script=joinpath(proj, "smoke.jl"),
                host_root=proj,
                local_workers=0,
                remote_hosts=remote_tokens,
                drive_flags=["-y", "-q", "--require-git"],
                extra_env=git_env,
            )
            _assert_ssh_e2e_ok(suite, "git_drive_require_git", proc, out)
            @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK", out)
        end
    end
end
