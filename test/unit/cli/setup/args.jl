using Test

@testset "setup args" begin
    parse_setup_args = DistSSHKit.parse_setup_args

    @test parse_setup_args(["--help"]).show_help
    @test parse_setup_args(["-h"]).show_help

    let r = parse_setup_args(["--check", "host1"])
        @test r.ignore_julia_version == false
    end
    let r = parse_setup_args(["--check", "--ignore-julia-version", "host1"])
        @test r.ignore_julia_version == true
    end

    let r = parse_setup_args(["--runtest", "host1"])
        @test r.mode == :runtest
        @test r.hosts == ["host1"]
    end

    let r = parse_setup_args(["--rsync", "host1", "host2"])
        @test r.mode == :rsync_push
        @test r.hosts == ["host1", "host2"]
    end

    let r = parse_setup_args(["--check", "--hosts-file", _sample_hosts_file(), "host-cli"])
        @test r.hosts == ["host-cli", "host-a", "host-b"]
    end

    let r = parse_setup_args(["--check", "--hosts", "h1:9,h2", "host-cli"])
        @test r.hosts == ["host-cli", "h1", "h2"]
    end

    withenv("DISTSSHKIT_HOSTS" => "env-h:3") do
        let r = parse_setup_args(["--check", "host-cli"])
            @test r.hosts == ["host-cli", "env-h"]
        end
    end

    @testset "help smoke (rsync-first)" begin
        txt = DistSSHKit.setup_help_text()
        @test occursin("--rsync", txt)
        @test occursin("--runtest", txt)
        @test occursin("--hosts", txt)
        @test occursin("Recommended:", txt)
        @test occursin("--require-git", txt)
        @test !occursin("day-to-day default", lowercase(txt))
        @test !occursin("drive needs --skip-git-guard", lowercase(txt))
    end
end
