using Test

@testset "size args" begin
    parse_size_args = DistSSHKit.parse_size_args

    @testset "parse_size_args" begin
        let r = parse_size_args(["masterhost", "host1", "host2"])
            @test r.show_help == false
            @test r.include_local == true
            @test r.hosts == ["host1", "host2"]
            @test r.gb_per_worker === nothing
            @test r.probe === nothing
            @test r.mem_headroom == DistSSHKit.DEFAULT_MEM_HEADROOM
            @test r.master_gb == DistSSHKit.DEFAULT_MASTER_GB
        end
        DistSSHKit._reset_deprecated_local_host_warning!()
        let r = parse_size_args(["local", "host1"])
            @test r.include_local == true
            @test r.hosts == ["host1"]
        end
        @test_throws ArgumentError parse_size_args(["--masterhost", "host1"])
        DistSSHKit._reset_deprecated_local_host_warning!()
        let r = parse_size_args(["--local", "host1", "host2"])
            @test r.show_help == false
            @test r.include_local == true
            @test r.hosts == ["host1", "host2"]
            @test r.gb_per_worker === nothing
            @test r.probe === nothing
            @test r.mem_headroom == DistSSHKit.DEFAULT_MEM_HEADROOM
            @test r.master_gb == DistSSHKit.DEFAULT_MASTER_GB
        end
        let r = parse_size_args(["--hosts", "h1:4,h2", "host-cli"])
            @test r.hosts == ["host-cli", "h1", "h2"]
        end
        let r = parse_size_args(["-l", "host1"])
            @test r.include_local == true
            @test r.hosts == ["host1"]
        end
        let r = parse_size_args(["--hosts-file", _sample_hosts_file(), "host-cli"])
            @test r.hosts == ["host-cli", "host-a", "host-b"]
        end
        let r = parse_size_args(["--version", "--local"])
            @test r.show_version
            @test r.include_local
        end
        # Unknown flags are warned and skipped (not an error).
        DistSSHKit._reset_deprecated_local_host_warning!()
        let r = @test_logs (:warn, r"Unknown option") (:warn, r"0\.4") parse_size_args(["--nope", "--local"])
            @test r.include_local
            @test isempty(r.hosts)
        end
        @test_throws ArgumentError parse_size_args(["--gb-per-worker"])
        @test_throws ArgumentError parse_size_args(["--probe"])
        withenv("DISTSSHKIT_HOSTS" => "env-h:2") do
            let r = parse_size_args(["host-cli"])
                @test r.hosts == ["host-cli", "env-h"]
            end
        end
        let r = parse_size_args(["--gb-per-worker", "1.5", "host1"])
            @test r.gb_per_worker == 1.5
            @test r.hosts == ["host1"]
        end
        let r = parse_size_args(["--probe", "warmup.jl", "--local"])
            @test r.probe == "warmup.jl"
            @test r.include_local == true
        end
        let r = parse_size_args(["--mem-headroom", "0.5", "--master-gb", "0.2"])
            @test r.mem_headroom == 0.5
            @test r.master_gb == 0.2
            @test isempty(r.hosts)
        end
        withenv("DISTSSHKIT_SIZE_PROBE" => "env_warmup.jl") do
            r = parse_size_args(["--local"])
            @test r.probe == "env_warmup.jl"
        end
        withenv("DISTSSHKIT_SIZE_PROBE" => "env_warmup.jl") do
            r = parse_size_args(["--probe", "cli_warmup.jl", "--local"])
            @test r.probe == "cli_warmup.jl"  # CLI wins over ENV
        end
        let path = tempname()
            r = parse_size_args(["--help"])
            @test r.show_help == true
            @test parse_size_args(["-h"]).show_help == true
            open(path, "w") do io
                DistSSHKit.show_size_usage(; io=io)
            end
            help = read(path, String)
            rm(path; force=true)
            @test occursin("DistSSHKit size", help)
            @test occursin("masterhost", help)
            @test occursin("--local", help)
            @test occursin("--gb-per-worker", help)
            @test occursin("--probe", help)
            @test occursin("--hosts", help)
            @test !occursin("#!/usr/bin/env julia", help)
            @test !occursin("function size_main", help)
        end
    end

    @testset "print_size_report matches compute_worker_plan" begin
        pw = 2.0
        plan = DistSSHKit.compute_worker_plan(
            ["localhost"], String[], Dict("localhost" => pw);
            mem_headroom=DistSSHKit.DEFAULT_MEM_HEADROOM,
            master_gb=DistSSHKit.DEFAULT_MASTER_GB,
        )
        opts = (
            show_help=false,
            show_version=false,
            cli_session=nothing,
            gb_per_worker=pw,
            probe=nothing,
            mem_headroom=DistSSHKit.DEFAULT_MEM_HEADROOM,
            master_gb=DistSSHKit.DEFAULT_MASTER_GB,
            include_local=true,
            hosts=String[],
        )
        samples = Dict(
            "localhost" => DistSSHKit.WorkerMemorySample(pw, pw),
        )
        path = tempname()
        open(path, "w") do io
            redirect_stdout(io) do
                DistSSHKit.print_size_report(["localhost"], String[], samples, opts)
            end
        end
        out = read(path, String)
        rm(path; force=true)
        @test occursin("Workers", out)
        @test occursin("masterhost", out)
        @test occursin("masterhost:$(plan.local_workers)", out)
        @test occursin("Total: $(plan.local_workers) workers", out)
        @test !occursin("Suggested", out)
    end

    @testset "print_size_report show_peak columns" begin
        opts = (
            show_help=false,
            show_version=false,
            cli_session=nothing,
            gb_per_worker=nothing,
            probe="warmup.jl",
            mem_headroom=DistSSHKit.DEFAULT_MEM_HEADROOM,
            master_gb=DistSSHKit.DEFAULT_MASTER_GB,
            include_local=true,
            hosts=String[],
        )
        samples = Dict(
            "localhost" => DistSSHKit.WorkerMemorySample(0.5, 1.5),
        )
        path = tempname()
        open(path, "w") do io
            redirect_stdout(io) do
                DistSSHKit.print_size_report(["localhost"], String[], samples, opts; show_peak=true)
            end
        end
        out = read(path, String)
        rm(path; force=true)
        @test occursin("Baseline", out)
        @test occursin("Peak", out)
        @test occursin("0.5 GB", out)
        @test occursin("1.5 GB", out)
        # Counts use effective = max(0.5, 1.5) = 1.5
        plan = DistSSHKit.compute_worker_plan(
            ["localhost"], String[], Dict("localhost" => 1.5);
            mem_headroom=DistSSHKit.DEFAULT_MEM_HEADROOM,
            master_gb=DistSSHKit.DEFAULT_MASTER_GB,
        )
        @test occursin("masterhost:$(plan.local_workers)", out)
    end

    @testset "run_size --gb-per-worker --local" begin
        # In-process size CLI. No SSH. Parser tests above do not run size_main.
        mktemp() do path, io
            code = withenv("DISTSSHKIT_CLI_SUBCOMMAND_DONE" => "") do
                redirect_stderr(devnull) do
                    redirect_stdout(io) do
                        DistSSHKit.run_size(["--gb-per-worker", "2", "--local"])
                    end
                end
            end
            flush(io)
            out = read(path, String)
            local_total, local_nproc = DistSSHKit.get_local_resources()
            expected = DistSSHKit.size_worker_count(
                local_total, local_nproc, 2.0; is_localhost=true,
            )
            @test code == 0
            @test occursin("masterhost:$(expected)", out)
            @test occursin("Total: $(expected) workers", out)
        end
    end
end
