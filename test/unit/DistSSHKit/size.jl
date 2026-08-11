using Test

@testset "size" begin
    @testset "size_worker_count" begin
        @test DistSSHKit.size_worker_count(16.0, 8, 2.0; mem_headroom=0.75, master_gb=0.4, is_localhost=true) ==
            min(max(0, floor(Int, (16.0 * 0.75 - 0.4) / 2.0)), max(1, 8 - 2))
        @test DistSSHKit.size_worker_count(16.0, 8, 2.0; mem_headroom=0.75, master_gb=0.4, is_localhost=false) ==
            min(max(0, floor(Int, (16.0 * 0.75) / 2.0)), max(1, 8 - 1))
        @test DistSSHKit.size_worker_count(1.0, 4, 2.0; is_localhost=false) == 0
        # CPU reserve on localhost with 2 cores → max(1, 0) = 1 caps the result.
        @test DistSSHKit.size_worker_count(32.0, 2, 1.0; is_localhost=true) == 1
    end

    @testset "rss_bytes_to_worker_gb" begin
        @test DistSSHKit.rss_bytes_to_worker_gb(0) == DistSSHKit.WORKER_MEMORY_GB_FALLBACK
        one_gb = 1024^3
        @test DistSSHKit.rss_bytes_to_worker_gb(one_gb) ==
            round(max(1.0 * DistSSHKit.WORKER_RSS_SAFETY_FACTOR, DistSSHKit.WORKER_MEMORY_GB_FLOOR), digits=2)
        @test DistSSHKit.MEMORY_CAPACITY_FRACTION == DistSSHKit.DEFAULT_MEM_HEADROOM
    end

    @testset "resolve_host_project_abs localhost" begin
        mktempdir() do tmp
            p = abspath(tmp)
            @test DistSSHKit.resolve_host_project_abs("localhost", p) ==
                DistSSHKit.canonical_local_path(p)
            @test DistSSHKit.resolve_host_path_abs("localhost", joinpath(p, "sub"), p) ==
                DistSSHKit.canonical_local_path(joinpath(p, "sub"))
        end
    end

    @testset "resolve_host_path_abs absolute remote map" begin
        mktempdir() do tmp
            p = DistSSHKit.canonical_local_path(tmp)
            withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/remote/App") do
                # Absolute mapped path short-circuits SSH in resolve_remote_abs_path_on_host.
                @test DistSSHKit.resolve_host_project_abs("some-host", p) == "/remote/App"
                @test DistSSHKit.resolve_host_path_abs("some-host", joinpath(p, "src"), p) ==
                    joinpath("/remote/App", "src") |> abspath
            end
        end
    end

    @testset "compute_worker_plan matches size_worker_count" begin
        # Use only localhost so remote SSH is not required.
        local_total, local_nproc = DistSSHKit.get_local_resources()
        pw = 2.0
        expected = DistSSHKit.size_worker_count(
            local_total,
            local_nproc,
            pw;
            mem_headroom=0.75,
            master_gb=0.4,
            is_localhost=true,
        )
        plan = DistSSHKit.compute_worker_plan(
            ["localhost"],
            String[],
            Dict("localhost" => pw);
            mem_headroom=0.75,
            master_gb=0.4,
        )
        @test plan.local_workers == expected
        @test isempty(plan.remote_workers)
    end

    @testset "size_plan with gb_per_worker" begin
        mktempdir() do tmp
            session = DistSSHKit.KitSession(
                project=tmp,
                workers=String[],
                include_local_for_size=true,
            )
            plan = DistSSHKit.size_plan(session; gb_per_worker=2.0)
            local_total, local_nproc = DistSSHKit.get_local_resources()
            @test plan.local_workers == DistSSHKit.size_worker_count(
                local_total, local_nproc, 2.0; is_localhost=true,
            )
        end
    end

    @testset "size_plan uses effective GB from probe samples" begin
        # Manual samples via gb_per_worker path already covered; here ensure
        # effective_worker_gb feeds plan math when peak > baseline.
        s = DistSSHKit.WorkerMemorySample(0.5, 2.0)
        @test DistSSHKit.effective_worker_gb(s) == 2.0
        local_total, local_nproc = DistSSHKit.get_local_resources()
        expected = DistSSHKit.size_worker_count(
            local_total, local_nproc, 2.0; is_localhost=true,
        )
        plan = DistSSHKit.compute_worker_plan(
            ["localhost"], String[], DistSSHKit.per_worker_gb_dict(Dict("localhost" => s)),
        )
        @test plan.local_workers == expected
    end

    @testset "WorkerMemorySample effective" begin
        s = DistSSHKit.WorkerMemorySample(0.5, 1.2)
        @test DistSSHKit.effective_worker_gb(s) == 1.2
        @test DistSSHKit.per_worker_gb_dict(Dict("localhost" => s))["localhost"] == 1.2
    end

    @testset "measure_rss with probe (local)" begin
        mktempdir() do tmp
            write(joinpath(tmp, "Project.toml"), "name = \"ProbeTmp\"\nuuid = \"11111111-1111-1111-1111-111111111111\"\nversion = \"0.0.1\"\n")
            mkdir(joinpath(tmp, "src"))
            write(joinpath(tmp, "src", "ProbeTmp.jl"), "module ProbeTmp\nend\n")
            probe = joinpath(tmp, "warmup.jl")
            # ~8 MiB allocation — may or may not move rounded GB; peak >= baseline still holds.
            write(probe, "const _SIZE_WARMUP = zeros(Float64, 1_000_000)\n")
            samples = DistSSHKit.measure_rss(tmp, String[]; include_local=true, probe=probe)
            @test haskey(samples, "localhost")
            s = samples["localhost"]
            @test s.baseline_gb >= DistSSHKit.WORKER_MEMORY_GB_FLOOR
            @test s.peak_gb >= s.baseline_gb
            @test DistSSHKit.effective_worker_gb(s) == max(s.baseline_gb, s.peak_gb)
        end
    end

    @testset "resolve_size_probe_path" begin
        mktempdir() do tmp
            p = DistSSHKit.canonical_local_path(tmp)
            @test DistSSHKit.resolve_size_probe_path(p, "warmup.jl") ==
                joinpath(p, "warmup.jl")
            abs_probe = joinpath(p, "abs.jl")
            @test DistSSHKit.resolve_size_probe_path(p, abs_probe) == abs_probe
            @test_throws ArgumentError DistSSHKit.resolve_size_probe_path(p, "  ")
        end
    end

    @testset "measure_rss missing probe throws" begin
        mktempdir() do tmp
            @test_throws ArgumentError DistSSHKit.measure_rss(
                tmp, String[]; include_local=true, probe="missing_warmup.jl",
            )
        end
    end

    @testset "PipelineConfig size_probe / DISTSSHKIT_SIZE_PROBE" begin
        mktempdir() do tmp
            driver = joinpath(tmp, "job.jl")
            write(driver, "")
            cfg = DistSSHKit.PipelineConfig(driver=driver, size_probe="warmup.jl")
            @test cfg.size_probe == "warmup.jl"
            withenv(
                "DRIVER" => driver,
                "DISTSSHKIT_SIZE_PROBE" => "from_env.jl",
                "DISTSSHKIT_HOSTS" => "",
                "DISTSSHKIT_HOSTS_FILE" => "",
                "SYNC_MODE" => "off",
                "GB_PER_WORKER" => nothing,
            ) do
                env_cfg = DistSSHKit.pipeline_config_from_env()
                @test env_cfg.size_probe == "from_env.jl"
            end
        end
    end
end
