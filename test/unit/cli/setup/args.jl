using Test

@testset "setup args" begin
    parse_setup_args = DistSSHKit.parse_setup_args

    @test parse_setup_args(["--help"]).show_help
    @test parse_setup_args(["-h"]).show_help

    let r = parse_setup_args(["--check", "child:host1"])
        @test r.ignore_julia_version == false
    end
    let r = parse_setup_args(["--check", "--ignore-julia-version", "child:host1"])
        @test r.ignore_julia_version == true
    end

    let r = parse_setup_args(["--runtest", "child:host1"])
        @test r.mode == :runtest
        @test r.hosts == ["host1"]
    end

    let r = parse_setup_args(["--rsync", "child:host1", "child:host2"])
        @test r.mode == :rsync_push
        @test r.hosts == ["host1", "host2"]
    end

    for (flag, mode) in (
        "--clone" => :clone,
        "--sync" => :sync,
        "--pull" => :pull,
        "--instantiate" => :instantiate,
        "--juliaup" => :juliaup,
        "--cleanup" => :cleanup,
        "--prune" => :prune,
        "--delete" => :delete,
        "--requirements" => :requirements,
    )
        let r = parse_setup_args([flag, "child:host1"])
            @test r.mode == mode
            @test r.hosts == ["host1"]
        end
    end

    # Last mode token wins; earlier flags are not rejected.
    let r = parse_setup_args(["--check", "--rsync", "child:host1"])
        @test r.mode == :rsync_push
    end

    let r = parse_setup_args(["--clone", "--repo", "git@ex/app.git", "child:host1"])
        @test r.repo_url == "git@ex/app.git"
        @test r.mode == :clone
    end
    let r = parse_setup_args(["--check", "--remote-path", "~/work/App.jl", "child:host1"])
        @test r.remote_path_override == "~/work/App.jl"
    end
    let r = parse_setup_args(["--check", "--remote-dir", "/tmp/App.jl", "child:host1"])
        @test r.remote_path_override == "/tmp/App.jl"
    end
    let r = parse_setup_args(["--check", "--julia", "/opt/julia/bin/julia", "child:host1"])
        @test r.julia_path == "/opt/julia/bin/julia"
    end
    let r = parse_setup_args(["--version", "--check", "child:host1"])
        @test r.show_version
        @test r.mode == :check
    end
    let r = parse_setup_args(["--prune", "--older-than", "7", "--id", "pi_file", "child:host1"])
        @test r.mode == :prune
        @test r.older_days == 7
        @test r.prune_id == "pi_file"
    end
    @test_throws ArgumentError parse_setup_args(["--check", "--older-than", "1", "child:host1"])
    @test_throws ArgumentError parse_setup_args(["--prune", "--older-than", "-1", "child:host1"])
    @test_throws ArgumentError parse_setup_args(["--julia"])
    @test_throws ArgumentError parse_setup_args(["--check", "host1"])

    let r = parse_setup_args(["--juliaup", "parent", "child:host1"])
        @test r.mode == :juliaup
        @test r.hosts == ["parent", "host1"]
    end
    let r = parse_setup_args(["--juliaup", "child:host1:4"])
        @test r.hosts == ["host1"]
    end

    let r = parse_setup_args(["--check", "--hosts-file", _sample_hosts_file(), "child:host-cli"])
        @test r.hosts == ["host-cli", "host-a", "host-b"]
    end

    let r = parse_setup_args(["--check", "--hosts", "child:h1:9,child:h2", "child:host-cli"])
        @test r.hosts == ["host-cli", "h1", "h2"]
    end

    withenv("DISTSSHKIT_HOSTS" => "child:env-h:3") do
        let r = parse_setup_args(["--check", "child:host-cli"])
            @test r.hosts == ["host-cli", "env-h"]
        end
    end

    @testset "help smoke (rsync-first)" begin
        txt = DistSSHKit.setup_help_text()
        @test occursin("--prune", txt)
        @test occursin("--older-than", txt)
        @test occursin("--runtest", txt)
        @test occursin("--juliaup", txt)
        @test occursin("--hosts", txt)
        @test occursin("child:host1", txt)
        @test occursin("parent", txt)
        @test occursin("progress DIR", txt)
        @test occursin("Recommended:", txt)
        @test occursin("--require-git", txt)
        @test occursin("DISTSSHKIT_JOBS", txt)
        @test occursin("confirm unless -y", txt)
        @test !occursin("day-to-day default", lowercase(txt))
        @test !occursin("drive needs --skip-git-guard", lowercase(txt))
    end
end
