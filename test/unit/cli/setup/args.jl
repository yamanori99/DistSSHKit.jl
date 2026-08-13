using Test

@testset "setup args" begin
    _setup_dir = joinpath(_kit_root(), "src", "cli", "setup")
    isdefined(Main, :parse_setup_args) || include(joinpath(_setup_dir, "args.jl"))

    @test parse_setup_args(["--help"]).show_help
    @test parse_setup_args(["-h"]).show_help

    let r = parse_setup_args(["--check", "host1"])
        @test r.ignore_julia_version == false
    end
    let r = parse_setup_args(["--check", "--ignore-julia-version", "host1"])
        @test r.ignore_julia_version == true
    end

    let r = parse_setup_args(["--rsync", "host1", "host2"])
        @test r.mode == :rsync_push
        @test r.hosts == ["host1", "host2"]
    end

    let r = parse_setup_args(["--check", "--hosts-file", _sample_hosts_file(), "host-cli"])
        @test r.hosts == ["host-cli", "host-a", "host-b"]
    end

    @testset "help smoke (rsync-first)" begin
        txt = setup_help_text()
        @test occursin("--rsync", txt)
        @test occursin("Workflow (recommended)", txt) || occursin("recommended", lowercase(txt))
        @test occursin("--require-git", txt) || occursin("git parity", lowercase(txt))
        @test !occursin("day-to-day default", lowercase(txt))
        @test !occursin("drive needs --skip-git-guard", lowercase(txt))
    end
end
