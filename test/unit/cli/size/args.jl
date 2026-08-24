using Test

@testset "size args" begin
    parse_size_args = DistSSHKit.parse_size_args

    @testset "parse_size_args" begin
        let r = parse_size_args(["parent", "child:host1", "child:host2"])
            @test !r.show_help
            @test r.include_local
            @test r.hosts == ["host1", "host2"]
            @test r.gb_per_worker === nothing
            @test r.probe === nothing
            @test r.mem_headroom == DistSSHKit.DEFAULT_MEM_HEADROOM
            @test r.master_gb == DistSSHKit.DEFAULT_MASTER_GB
        end
        let r = parse_size_args(["child:local", "child:host1"])
            @test !r.include_local
            @test r.hosts == ["local", "host1"]
        end
        @test_throws ArgumentError parse_size_args(["--parent", "child:host1"])
        @test_throws ArgumentError parse_size_args(["--masterhost", "child:host1"])
        @test_throws ArgumentError parse_size_args(["--local", "child:host1", "child:host2"])
        let r = parse_size_args(["--hosts", "child:h1:4,child:h2", "child:host-cli"])
            @test r.hosts == ["host-cli", "h1", "h2"]
        end
        @test_throws ArgumentError parse_size_args(["-l", "child:host1"])
        let r = parse_size_args(["--hosts-file", _sample_hosts_file(), "child:host-cli"])
            @test r.hosts == ["host-cli", "host-a", "host-b"]
        end
        @test_throws ArgumentError parse_size_args(["--version", "--local"])
        # Unknown flags are warned and skipped (not an error).
        let r = @test_logs (:warn, r"Unknown option") parse_size_args(["--nope"])
            @test isempty(r.hosts)
        end
        @test_logs (:warn, r"Unknown option") begin
            @test_throws ArgumentError parse_size_args(["--nope", "--local"])
        end
        @test_throws ArgumentError parse_size_args(["--gb-per-worker"])
        @test_throws ArgumentError parse_size_args(["--probe"])
        withenv("DISTSSHKIT_HOSTS" => "child:env-h:2") do
            let r = parse_size_args(["child:host-cli"])
                @test r.hosts == ["host-cli", "env-h"]
            end
        end
        let r = parse_size_args(["--gb-per-worker", "1.5", "child:host1"])
            @test r.gb_per_worker == 1.5
            @test r.hosts == ["host1"]
        end
        @test_throws ArgumentError parse_size_args(["--probe", "warmup.jl", "--local"])
        let r = parse_size_args(["--mem-headroom", "0.5", "--master-gb", "0.2"])
            @test r.mem_headroom == 0.5
            @test r.master_gb == 0.2
            @test isempty(r.hosts)
        end
        withenv("DISTSSHKIT_SIZE_PROBE" => "env_warmup.jl") do
            r = parse_size_args(["parent"])
            @test r.probe == "env_warmup.jl"
            @test r.include_local
        end
        withenv("DISTSSHKIT_SIZE_PROBE" => "env_warmup.jl") do
            r = parse_size_args(["--probe", "cli_warmup.jl", "parent"])
            @test r.probe == "cli_warmup.jl"  # CLI wins over ENV
        end
        let path = tempname()
            r = parse_size_args(["--help"])
            @test r.show_help
            @test parse_size_args(["-h"]).show_help
            open(path, "w") do io
                DistSSHKit.show_size_usage(; io=io)
            end
            help = read(path, String)
            rm(path; force=true)
            @test occursin("DistSSHKit size", help)
            @test occursin("parent", help)
            @test !occursin("--local", help)
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
            ["parent"], String[], Dict("parent" => pw);
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
            "parent" => DistSSHKit.WorkerMemorySample(pw, pw),
        )
        path = tempname()
        open(path, "w") do io
            redirect_stdout(io) do
                DistSSHKit.print_size_report(["parent"], String[], samples, opts)
            end
        end
        out = read(path, String)
        rm(path; force=true)
        @test occursin("Workers", out)
        @test occursin("parent", out)
        @test occursin("parent:$(plan.local_workers)", out)
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
            "parent" => DistSSHKit.WorkerMemorySample(0.5, 1.5),
        )
        path = tempname()
        open(path, "w") do io
            redirect_stdout(io) do
                DistSSHKit.print_size_report(["parent"], String[], samples, opts; show_peak=true)
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
            ["parent"], String[], Dict("parent" => 1.5);
            mem_headroom=DistSSHKit.DEFAULT_MEM_HEADROOM,
            master_gb=DistSSHKit.DEFAULT_MASTER_GB,
        )
        @test occursin("parent:$(plan.local_workers)", out)
    end

    @testset "run_size --gb-per-worker parent" begin
        # In-process size CLI. No SSH. Parser tests above do not run size_main.
        mktemp() do path, io
            code = withenv("DISTSSHKIT_CLI_SUBCOMMAND_DONE" => "") do
                redirect_stderr(devnull) do
                    redirect_stdout(io) do
                        DistSSHKit.run_size(["--gb-per-worker", "2", "parent"])
                    end
                end
            end
            flush(io)
            out = read(path, String)
            local_total, local_nproc = DistSSHKit.get_local_resources()
            expected = DistSSHKit.size_worker_count(
                local_total, local_nproc, 2.0; is_parenthost=true,
            )
            @test code == 0
            @test occursin("parent:$(expected)", out)
            @test occursin("Total: $(expected) workers", out)
        end
    end
end
