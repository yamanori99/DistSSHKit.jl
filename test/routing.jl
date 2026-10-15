# `main` wording and streams. Not a guarantee of every help sentence.

@testset "main" begin
    let (code, out, err) = _main_capture(String[])
        @test code == 1
        @test isempty(out)
        @test occursin("Usage", err)
        @test occursin("julia -m DistSSHKit <command>", err)
        @test occursin("submit", err)
    end
    let (code, out, err) = _main_capture(["bogus"])
        @test code == 1
        @test isempty(out)
        @test occursin("Unknown subcommand: bogus", err)
        @test occursin("submit", err)
    end
    let (code, out, err) = _main_capture(["map_echo.jl"])
        @test code == 1
        @test isempty(out)
        @test occursin("does not infer go / ride / drive", err)
        @test occursin("go SCRIPT.jl", err)
        @test !occursin("Unknown subcommand", err)
    end
    let (code, out, err) = _main_capture(["parent:2", "job.jl"])
        @test code == 1
        @test isempty(out)
        @test occursin("does not infer go / ride / drive", err)
    end
    let (code, out, err) = _main_capture(["--help"])
        @test code == 0
        @test isempty(out)
        @test occursin("Usage", err)
        @test occursin("progress", err)
        @test occursin("submit", err)
        @test occursin("qhost setup", err)
        @test !occursin("julia -m DistSSHQueue", err)
    end
    let (code, out, err) = _main_capture(["go", "--help"])
        @test code == 0
        @test occursin("DistSSHKit go", out)
        @test occursin("Usage", out)
        @test !occursin("Unknown subcommand", out)
        @test !occursin("Unknown subcommand", err)
    end
    let (code, out, err) = _main_capture(["setup", "--help"])
        @test code == 0
        @test occursin("DistSSHKit setup", out)
        @test occursin("--clone", out)
        @test !occursin("Unknown subcommand", err)
    end
    let (code, out, err) = _main_capture(["submit", "--help"])
        @test code == 0
        @test occursin("DistSSHKit submit", out)
        @test !occursin("Unknown subcommand", out * err)
    end
    let (code, out, err) = _main_capture(["--help", "client"])
        @test code == 0
        @test occursin("DistSSHKit --help client", out)
        @test occursin("submit", out)
        @test occursin("Jobs", out)
        @test !occursin("Unknown subcommand", err)
    end
    let (code, out, err) = _main_capture(["qhost", "setup", "--help"])
        @test code == 0
        @test occursin("DistSSHKit qhost setup", out)
        @test occursin("--force", out)
        @test !occursin("clone", lowercase(out * err))
    end
    let (code, out, err) = _main_capture(["qhost:HOST", "submit", "--help"])
        @test code == 0
        @test occursin("DistSSHKit submit", out)
        @test !occursin("Unknown subcommand", out * err)
    end
end
