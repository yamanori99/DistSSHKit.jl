# `main` wording and streams, and the `_route` table. Not a guarantee of
# every help sentence. Rows marked "separate decision" record today's
# destination. They do not choose whether that destination is the spec.

using Random

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

let routes = [
        (String[], (:usage, 1)),
        (["-h"], (:usage, 0)),
        (["help"], (:usage, 0)),
        (["--help"], (:usage, 0)),
        (["-v"], (:version, String[])),
        (["-V"], (:version, String[])),
        (["--version"], (:version, String[])),
        (["go", "-v"], (:version, String[])),
        (["go", "--version"], (:version, String[])),
        (["go", "-v", "extra"], (:run, ["go", "-v", "extra"])),
        (["qhost"], (:queue, String[])),
        (["qhost", "setup"], (:queue, ["setup"])),
        (["--remote-julia", "J", "qhost", "setup"], (:queue, ["--remote-julia", "J", "setup"])),
        (["--queue-env", "E", "qhost", "serve"], (:queue, ["--queue-env", "E", "serve"])),
        (["--remote-julia"], (:unknown, "--remote-julia")), # R10
        (["--queue-env", "E", "status"], (:queue, ["--queue-env", "E", "status"])),
        # R1. Separate decision: a run command after `--project=` goes to the queue.
        (["--project=.", "go", "x.jl"], (:queue, ["--project=.", "go", "x.jl"])),
        (["--project", "P"], (:queue, ["--project", "P"])),
        (["--qhost"], (:queue, ["--qhost"])),
        # R2. Separate decision: `qhost:` after the verb goes to the queue.
        (["go", "qhost:H"], (:queue, ["go", "qhost:H"])),
        (["status", "qhost:H"], (:queue, ["status", "qhost:H"])),
        (["qhost:H", "qhost", "setup"], (:queue, ["qhost:H", "qhost", "setup"])),
        (["qhost:HOST", "submit", "--help"], (:queue, ["qhost:HOST", "submit", "--help"])),
        # R3. Separate decision: `submit --version` is the queue, unlike `go --version`.
        (["submit", "--version"], (:queue, ["submit", "--version"])),
        (["--help", "client"], (:queue_help, ["--help", "client"])),
        (["--help", "qhost"], (:queue_help, ["--help", "qhost"])),
        (["--help", "queue"], (:queue_help, ["--help", "queue"])),
        (["--help", "queue-host"], (:queue_help, ["--help", "queue-host"])),
        (["-h", "client"], (:queue_help, ["-h", "client"])),
        (["go", "x.jl"], (:run, ["go", "x.jl"])),
        (["x.jl"], (:no_command, "x.jl")),
        (["map_echo.jl"], (:no_command, "map_echo.jl")),
        (["bogus"], (:unknown, "bogus")),
        # R4. Separate decision: `-h` with an extra word is an unknown subcommand.
        (["-h", "bogus"], (:unknown, "-h")),
        # R5. Separate decision: `help <command>` is an unknown subcommand.
        (["help", "go"], (:unknown, "help")),
        # R8. Separate decision: an empty word is an unknown subcommand.
        ([""], (:unknown, "")),
        # R13. Separate decision: `--version` with an extra word is unknown.
        (["--version", "extra"], (:unknown, "--version")),
    ]
    @testset "route $(repr(a))" for (a, want) in routes
        @test DistSSHKit._route(a) == want
    end
end

@testset "route never throws" begin
    tokens = String[
        "go", "submit", "qhost", "qhost:H", "--remote-julia", "--queue-env",
        "--project", "--project=.", "--qhost", "-h", "--help", "-v",
        "x.jl", "", "ü", "--",
    ]
    rng = Xoshiro(20261015)
    thrown = nothing
    for _ in 1:1000
        n = rand(rng, 0:5)
        a = String[rand(rng, tokens) for _ in 1:n]
        try
            DistSSHKit._route(a)
        catch e
            thrown = (a, e)
            break
        end
    end
    @test thrown === nothing
end
