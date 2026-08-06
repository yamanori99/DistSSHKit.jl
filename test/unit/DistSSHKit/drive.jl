using Test

@testset "drive API" begin
    @testset "KitSession" begin
        mktempdir() do tmp
            withenv("DISTSSHKIT_HOSTS_FILE" => "") do
                session = DistSSHKit.KitSession(project=tmp, hosts=["host-a", "host-b:4"])
                @test session.project == abspath(tmp)
                @test session.hosts == ["host-a", "host-b"]
                @test session.remote_root === nothing
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
        mktempdir() do tmp
            session = DistSSHKit.KitSession(
                project=tmp,
                hosts=["host-a"],
                remote_root="/remote/App.jl",
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
            hosts=["host-a"],
            sync=:rsync,
        )
        session = DistSSHKit.kit_session_from_config(cfg)
        @test DistSSHKit.resolve_pipeline_sync(cfg, session) === :rsync
        @test DistSSHKit.resolve_pipeline_collect(cfg, session)

        # Git parity off by default; sync mode does not flip it.
        default_cfg = DistSSHKit.PipelineConfig(driver="job.jl", hosts=["host-a"])
        default_session = DistSSHKit.kit_session_from_config(default_cfg)
        @test DistSSHKit.resolve_pipeline_sync(default_cfg, default_session) === false
        @test DistSSHKit.pipeline_skip_hash_check(default_cfg)
        @test DistSSHKit.pipeline_skip_hash_check(
            DistSSHKit.PipelineConfig(driver="job.jl", hosts=["host-a"], sync=:sync),
        )
        @test !DistSSHKit.pipeline_skip_hash_check(
            DistSSHKit.PipelineConfig(
                driver="job.jl",
                hosts=["host-a"],
                skip_hash_check=false,
            ),
        )

        local_cfg = DistSSHKit.PipelineConfig(
            driver="job.jl",
            include_local_for_size=true,
            sync=false,
            collect=false,
        )
        local_session = DistSSHKit.kit_session_from_config(local_cfg)
        @test DistSSHKit.resolve_pipeline_sync(local_cfg, local_session) === false
        @test !DistSSHKit.resolve_pipeline_collect(local_cfg, local_session)

        mktempdir() do tmp
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
    end

    @testset "drive_parsed_from_session sync / parity" begin
        mktempdir() do tmp
            script = joinpath(tmp, "job.jl")
            write(script, "")
            session = DistSSHKit.KitSession(project=tmp, hosts=["host-a"])
            DistSSHKit._ensure_drive_fragments!(tmp)

            parsed = DistSSHKit.drive_parsed_from_session(session, script)
            @test parsed.sync_mode === nothing
            @test parsed.skip_hash_check == true

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

    @testset "pipeline_config_from_env" begin
        withenv(
            "DISTSSHKIT_HOSTS" => "host-a, host-b",
            "DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/remote/App",
            "DRIVER" => "demos/job.jl",
            "SYNC_MODE" => "off",
            "GB_PER_WORKER" => "2.0",
            "DISTSSHKIT_HOSTS_FILE" => "",
        ) do
            cfg = DistSSHKit.pipeline_config_from_env()
            @test cfg.hosts == ["host-a", "host-b"]
            @test cfg.remote_root == "/remote/App"
            @test cfg.driver == "demos/job.jl"
            @test cfg.sync === false
            @test cfg.gb_per_worker == 2.0
        end
    end
end
