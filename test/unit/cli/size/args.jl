using Test

@testset "size args" begin
    isdefined(Main, :size_main) || include(joinpath(_kit_root(), "src", "cli", "size.jl"))

    @testset "parse_size_args" begin
        let r = parse_size_args(["--local", "host1", "host2"])
            @test r.show_help == false
            @test r.include_local == true
            @test r.hosts == ["host1", "host2"]
            @test r.gb_per_worker === nothing
            @test r.probe === nothing
            @test r.mem_headroom == DistSSHKit.DEFAULT_MEM_HEADROOM
            @test r.master_gb == DistSSHKit.DEFAULT_MASTER_GB
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
            open(path, "w") do io
                redirect_stdout(io) do
                    show_size_usage()
                end
            end
            help = read(path, String)
            rm(path; force=true)
            @test occursin("DistSSHKit size", help)
            @test occursin("--gb-per-worker", help)
            @test occursin("--probe", help)
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
                print_size_report(["localhost"], String[], samples, opts)
            end
        end
        out = read(path, String)
        rm(path; force=true)
        @test occursin("Workers", out)
        @test occursin("local:$(plan.local_workers)", out)
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
                print_size_report(["localhost"], String[], samples, opts; show_peak=true)
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
        @test occursin("local:$(plan.local_workers)", out)
    end
end
