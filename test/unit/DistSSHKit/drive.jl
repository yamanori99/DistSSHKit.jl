using Test

@testset "drive API" begin
    @testset "parse_worker_tokens" begin
        p = DistSSHKit.parse_worker_tokens(["local:2", "host-a:4", "host-b"])
        @test p.local_workers == 2
        @test !p.local_autosize
        @test p.remote_fixed == Dict("host-a" => 4)
        @test p.remote_auto == ["host-b"]
        @test p.remote_hosts == ["host-a", "host-b"]
        @test DistSSHKit.worker_tokens_fully_specified(p) == false

        fixed = DistSSHKit.parse_worker_tokens(["local:2", "h1:1"])
        @test DistSSHKit.worker_tokens_fully_specified(fixed)
        plan = DistSSHKit.worker_plan_from_tokens(["local:2", "h1:1"])
        @test plan.local_workers == 2
        @test plan.remote_workers == Dict("h1" => 1)
        err = try
            DistSSHKit.worker_plan_from_tokens(["h1"])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("KitSession", sprint(showerror, err))

        @test_throws ArgumentError DistSSHKit.parse_worker_tokens(["local:1", "l:2"])
    end

    @testset "KitSession" begin
        _with_tempdir() do tmp
            withenv("DISTSSHKIT_HOSTS_FILE" => "") do
                session = DistSSHKit.KitSession(project=tmp, workers=["host-a", "host-b:4"])
                @test session.project == abspath(tmp)
                @test session.hosts == ["host-a", "host-b"]
                @test session.tokens == ["host-a", "host-b:4"]
                @test session.remote === nothing
            end
        end
    end

    @testset "drive_host_specs" begin
        plan = DistSSHKit.WorkerPlan(2, Dict("host-a" => 4, "host-b" => 0))
        @test DistSSHKit.drive_host_specs(plan) == ["local:2", "host-a:4"]
    end

    @testset "compute_worker_plan" begin
        per_worker = Dict("localhost" => 1.0, "host-a" => 1.0)
        plan = DistSSHKit.compute_worker_plan(
            ["localhost", "host-a"],
            ["host-a"],
            per_worker;
            mem_headroom=0.75,
            master_gb=0.4,
        )
        @test plan.local_workers >= 0
        @test haskey(plan.remote_workers, "host-a")
        @test plan.remote_workers["host-a"] >= 0
    end

    @testset "apply_session_env!" begin
        _with_tempdir() do tmp
            session = DistSSHKit.KitSession(
                project=tmp,
                workers=["host-a"],
                remote="/remote/App.jl",
                quiet=true,
                yes=true,
            )
            DistSSHKit.apply_session_env!(session)
            @test ENV["DISTRIBUTED_PROJECT_ROOT"] == abspath(tmp)
            @test ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"] == "/remote/App.jl"
            @test DistSSHKit.kit_output_quiet()
            @test DistSSHKit.kit_noninteractive()
        end
        delete!(ENV, "DISTRIBUTED_PROJECT_ROOT")
        delete!(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT")
        DistSSHKit.set_kit_output_quiet!(false)
        DistSSHKit.set_kit_noninteractive!(false)
    end

    @testset "pipeline helpers" begin
        cfg = DistSSHKit.PipelineConfig(
            driver="job.jl",
            workers=["host-a"],
            sync=:rsync,
        )
        session = DistSSHKit.kit_session_from_config(cfg)
        @test DistSSHKit.resolve_pipeline_sync(cfg, session) === :rsync
        @test DistSSHKit.resolve_pipeline_collect(cfg, session)

        # Git parity off by default; sync mode does not flip it.
        default_cfg = DistSSHKit.PipelineConfig(driver="job.jl", workers=["host-a"])
        default_session = DistSSHKit.kit_session_from_config(default_cfg)
        @test DistSSHKit.resolve_pipeline_sync(default_cfg, default_session) === false
        @test DistSSHKit.pipeline_skip_hash_check(default_cfg)
        @test DistSSHKit.pipeline_skip_hash_check(
            DistSSHKit.PipelineConfig(driver="job.jl", workers=["host-a"], sync=:sync),
        )
        @test !DistSSHKit.pipeline_skip_hash_check(
            DistSSHKit.PipelineConfig(
                driver="job.jl",
                workers=["host-a"],
                skip_hash_check=false,
            ),
        )

        local_cfg = DistSSHKit.PipelineConfig(
            driver="job.jl",
            workers=["local:2"],
            sync=false,
            collect=false,
        )
        local_session = DistSSHKit.kit_session_from_config(local_cfg)
        @test DistSSHKit.resolve_pipeline_sync(local_cfg, local_session) === false
        @test !DistSSHKit.resolve_pipeline_collect(local_cfg, local_session)

        _with_tempdir() do tmp
            driver = joinpath(tmp, "job.jl")
            write(driver, "")
            od = joinpath(tmp, "my_out")
            cfg_od = DistSSHKit.PipelineConfig(driver=driver, output_dir=od)
            @test DistSSHKit.pipeline_collect_root(cfg_od) == abspath(od)
            withenv("DISTRIBUTED_OUTPUT_DIR" => joinpath(tmp, "env_out")) do
                cfg_env = DistSSHKit.PipelineConfig(driver=driver)
                @test DistSSHKit.pipeline_collect_root(cfg_env) ==
                    abspath(joinpath(tmp, "env_out"))
            end
            delete!(ENV, "DISTRIBUTED_OUTPUT_DIR")
            cfg_fallback = DistSSHKit.PipelineConfig(driver=driver)
            @test DistSSHKit.pipeline_collect_root(cfg_fallback) ==
                joinpath(dirname(abspath(driver)), "output")
        end

        @test DistSSHKit._parse_env_sync_mode("rsync") === :rsync
        @test DistSSHKit._parse_env_sync_mode("sync") === :sync
        @test DistSSHKit._parse_env_sync_mode("off") === false
        @test_throws ArgumentError DistSSHKit._parse_env_sync_mode("true")
        @test_throws ArgumentError DistSSHKit._parse_env_sync_mode("1")

        cfg_jl = DistSSHKit.PipelineConfig(
            driver="job.jl",
            workers=["host-a"],
            julia="/opt/julia/bin/julia",
        )
        @test cfg_jl.julia == "/opt/julia/bin/julia"
        @test DistSSHKit.PipelineConfig(driver="job.jl", julia="auto").julia === nothing
        @test DistSSHKit.PipelineConfig(driver="job.jl", julia="").julia === nothing
    end

    @testset "drive_parsed_from_session sync / parity" begin
        _with_tempdir() do tmp
            script = joinpath(tmp, "job.jl")
            write(script, "")
            session = DistSSHKit.KitSession(project=tmp, workers=["host-a"])
            DistSSHKit._ensure_drive_fragments!(tmp)

            parsed = DistSSHKit.drive_parsed_from_session(session, script)
            @test parsed.sync_mode === nothing
            @test parsed.skip_hash_check == true
            @test parsed.hint_surface === :api
            @test parsed.julia === nothing

            parsed_jl = DistSSHKit.drive_parsed_from_session(
                session,
                script;
                julia="/opt/julia/bin/julia",
            )
            @test parsed_jl.julia == "/opt/julia/bin/julia"
            @test DistSSHKit.drive_parsed_from_session(
                session,
                script;
                julia="auto",
            ).julia === nothing

            parsed_sync = DistSSHKit.drive_parsed_from_session(session, script; sync=:sync)
            @test parsed_sync.sync_mode === :sync
            @test parsed_sync.skip_hash_check == true

            parsed_require = DistSSHKit.drive_parsed_from_session(
                session,
                script;
                sync=:sync,
                skip_hash_check=false,
            )
            @test parsed_require.skip_hash_check == false

            # rsync has no remote .git/; parity stays off even if requested via API
            parsed_rsync = DistSSHKit.drive_parsed_from_session(
                session,
                script;
                sync=:rsync,
                skip_hash_check=false,
            )
            @test parsed_rsync.sync_mode === :rsync
            @test parsed_rsync.skip_hash_check == true
        end
    end

    @testset "instantiate! requires SSH hosts" begin
        _with_tempdir() do tmp
            session = DistSSHKit.KitSession(project=tmp, workers=["local:2"])
            @test_throws ArgumentError DistSSHKit.instantiate!(session)
        end
    end

    @testset "collect! requires hosts" begin
        _with_tempdir() do tmp
            session = DistSSHKit.KitSession(project=tmp, workers=["local:2"])
            err = try
                DistSSHKit.collect!(session, joinpath(tmp, "out"))
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("collect!", sprint(showerror, err))
        end
    end

    @testset "report_pipeline_errors" begin
        ok = DistSSHKit.PipelineResult(
            true, nothing, nothing, nothing, nothing, "job.jl",
        )
        @test DistSSHKit.report_pipeline_errors(ok)
        bad = DistSSHKit.PipelineResult(
            false,
            DistSSHKit.SyncResult(false, [DistSSHKit.HostResult("h1", false, "rsync refuse")], false),
            nothing,
            DistSSHKit.DriveResult(false, 1),
            DistSSHKit.CollectResult(false, 1),
            "job.jl";
            failed_step="drive",
        )
        buf = IOBuffer()
        @test !DistSSHKit.report_pipeline_errors(bad; io=buf)
        txt = String(take!(buf))
        @test occursin("pipeline! failed at step: drive", txt)
        @test occursin("sync h1: rsync refuse", txt)
        @test occursin("drive exit 1", txt)
        @test occursin("collect exit 1", txt)
    end

    @testset "pipeline! missing driver surfaces" begin
        _with_tempdir() do tmp
            missing = joinpath(tmp, "demos", "with_kit", "rho_sweep.jl")
            cfg = DistSSHKit.PipelineConfig(project=tmp, driver=missing, workers=String[])
            err = try
                DistSSHKit.pipeline!(cfg)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("driver not found", sprint(showerror, err))
            @test occursin("DistSSHKit.install_demos()", sprint(showerror, err))
        end
    end

    @testset "pipeline_config_from_env" begin
        withenv(
            "DISTSSHKIT_HOSTS" => "host-a, host-b",
            "DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/remote/App",
            "DRIVER" => "demos/job.jl",
            "SYNC_MODE" => "off",
            "GB_PER_WORKER" => "2.0",
            "DISTSSHKIT_HOSTS_FILE" => "",
            "JULIA_DISTRIBUTED_EXE" => "/opt/julia/bin/julia",
        ) do
            cfg = DistSSHKit.pipeline_config_from_env()
            @test cfg.tokens == ["host-a", "host-b"]
            @test cfg.remote == "/remote/App"
            @test cfg.driver == "demos/job.jl"
            @test cfg.sync === false
            @test cfg.gb_per_worker == 2.0
            @test cfg.julia == "/opt/julia/bin/julia"
        end
        withenv(
            "DRIVER" => "demos/job.jl",
            "DISTSSHKIT_HOSTS" => "",
            "DISTSSHKIT_HOSTS_FILE" => "",
            "JULIA_DISTRIBUTED_EXE" => "auto",
        ) do
            @test DistSSHKit.pipeline_config_from_env().julia === nothing
        end
    end
end
