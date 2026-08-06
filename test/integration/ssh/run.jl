#!/usr/bin/env julia
# Real-SSH E2E against testenv/docker-ssh workers.
#
#   DISTSSHKIT_SSH_E2E=1 julia --project=. test/integration/ssh/run.jl
#
# Afterward open only:
#   $(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt

using Test

kit_root = abspath(joinpath(@__DIR__, "..", "..", ".."))
include(joinpath(kit_root, "test", "support.jl"))

if !_ssh_e2e_enabled()
    @info "Skipping SSH E2E (set DISTSSHKIT_SSH_E2E=1 to enable)"
    exit(0)
end

g = _docker_ssh_generated()
if !isfile(g.ssh_config) || !isfile(g.hosts_file)
    error("docker-ssh not ready: missing $(g.ssh_config). Run testenv/docker-ssh/scripts/up.sh")
end

hosts = collect(String, _SSH_E2E_HOSTS)
remote_root = _SSH_E2E_REMOTE_ROOT
e2e_env = _ssh_e2e_env(; remote_project=remote_root)
remote_tokens = ["$(hosts[1]):1", "$(hosts[2]):1"]

@testset "SSH E2E (docker-ssh)" verbose=true begin
    _with_ssh_e2e_suite() do suite
        # --- local-only with_kit demos ---
        @testset "local with_kit demos" begin
            proj = suite.project_local
            demos_dir = joinpath(proj, "demos")
            mkpath(demos_dir)
            _stage_with_kit_demos!(demos_dir, kit_root)
            with_kit = joinpath(demos_dir, "with_kit")

            echo_script = joinpath(with_kit, "square_echo.jl")
            proc, out = _run_kit_drive(;
                script=echo_script,
                host_root=proj,
                local_workers=2,
                script_args=["3"],
                drive_flags=["-y", "-q"],
            )
            _assert_ssh_e2e_ok(suite, "local_square_echo", proc, out)
            @test occursin("param^2:", out)

            file_script = joinpath(with_kit, "square_file.jl")
            proc, out = _run_kit_drive(;
                script=file_script,
                host_root=proj,
                local_workers=2,
                script_args=["3"],
                drive_flags=["-y", "-q"],
            )
            _assert_ssh_e2e_ok(suite, "local_square_file", proc, out)
            @test occursin("wrote ", out) || occursin("Results:", out)
            file_csv = joinpath(with_kit, "output", "square_results.csv")
            @test isfile(file_csv)
            expected = join([
                "param,result",
                ("$n,$(n^2)" for n in 1:3)...,
            ], '\n') * '\n'
            @test read(file_csv, String) == expected
        end

        # --- remote suite (both docker workers) ---
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
            _ssh_e2e_record!(suite, "setup_delete", proc, out; expect_ok=true, project=proj, kit=:setup)
            if proc.exitcode != 0
                println(stderr, out)
            end
            @test proc.exitcode == 0
        end

        @testset "setup --rsync" begin
            proc, out = _run_kit_setup(;
                setup_args=["--rsync", "--remote-path", remote_root, hosts...],
                project_root=proj,
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "setup_rsync", proc, out; project=proj, kit=:setup)
        end

        @testset "setup --instantiate" begin
            proc, out = _run_kit_setup(;
                setup_args=["--instantiate", "--remote-path", remote_root, hosts...],
                project_root=proj,
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "setup_instantiate", proc, out; project=proj, kit=:setup)
        end

        @testset "setup --check" begin
            proc, out = _run_kit_setup(;
                setup_args=[
                    "--check",
                    "--ignore-julia-version",
                    "--remote-path",
                    remote_root,
                    hosts...,
                ],
                project_root=proj,
                extra_env=e2e_env,
            )
            _assert_ssh_e2e_ok(suite, "setup_check", proc, out; project=proj, kit=:setup)
        end

        @testset "size two remotes" begin
            proc, out = _run_kit_size(;
                size_args=["-q", hosts...],
                project_root=proj,
                extra_env=merge(e2e_env, Dict("DISTSSHKIT_QUIET" => "0")),
            )
            _assert_ssh_e2e_ok(suite, "size_remotes", proc, out)
            @test occursin(hosts[1], out) || occursin("Workers", out) || occursin("worker", lowercase(out))
            @test occursin(hosts[2], out) || occursin("Workers", out) || occursin("GB", out)
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
            @test count(r"π ≈", out) >= 2 || count(r"✓", out) >= 2
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
            @test occursin("π ≈", out) || occursin("wrote ", out)
            batch = _ssh_e2e_latest_go_batch(proj)
            @test batch !== nothing
            for host in hosts
                slot = joinpath(batch::String, host)
                @test isdir(slot)
                @test isfile(joinpath(slot, "pi_results.txt"))
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
            @test occursin("refusing", lowercase(out)) || occursin("already exists", lowercase(out))
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
    end
end
