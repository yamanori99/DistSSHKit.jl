# `main` wording and streams, and the `_route` table. Not a guarantee of
# every help sentence. A comment on a row says what that row records.

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
    let (code, out, err) = _main_capture(["--project=.", "go", "x.jl"])
        @test code == 1
        @test isempty(out)
        @test occursin("`--project` after `julia -m DistSSHKit`", err)
        @test occursin("before `-m`", err)
    end
    let (code, out, err) = _main_capture(["--queue-env", "E", "--project", "P", "status"])
        @test code == 1
        @test isempty(out)
        @test occursin("before `-m`", err)
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
        # `--remote-julia` without a path is not a command.
        (["--remote-julia"], (:unknown, "--remote-julia")),
        (["--queue-env", "E", "status"], (:queue, ["--queue-env", "E", "status"])),
        # A run command after `--project=` goes to the queue. `_main` then rejects it.
        (["--project=.", "go", "x.jl"], (:queue, ["--project=.", "go", "x.jl"])),
        (["--project", "P"], (:queue, ["--project", "P"])),
        (["--qhost"], (:queue, ["--qhost"])),
        # `qhost:` after the verb goes to the queue.
        (["go", "qhost:H"], (:queue, ["go", "qhost:H"])),
        (["status", "qhost:H"], (:queue, ["status", "qhost:H"])),
        (["qhost:H", "qhost", "setup"], (:queue, ["qhost:H", "qhost", "setup"])),
        (["qhost:HOST", "submit", "--help"], (:queue, ["qhost:HOST", "submit", "--help"])),
        # `submit --version` is the queue, unlike `go --version`.
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
        # `-h` with an extra word is an unknown subcommand.
        (["-h", "bogus"], (:unknown, "-h")),
        # `help <command>` is an unknown subcommand.
        (["help", "go"], (:unknown, "help")),
        # An empty word is an unknown subcommand.
        ([""], (:unknown, "")),
        # `--version` with an extra word is unknown.
        (["--version", "extra"], (:unknown, "--version")),
    ]
    @testset "route $(repr(a))" for (a, want) in routes
        @test DistSSHKit._route(a) == want
    end
end

@testset "each command routes alone" begin
    for c in DistSSHKit._RUN_COMMANDS
        @test DistSSHKit._route([c]) == (:run, [c])
        # One version flag after a run command is this package's version.
        @test DistSSHKit._route([c, "-v"]) == (:version, String[])
        @test DistSSHKit._route([c, "--version"]) == (:version, String[])
    end
    for c in DistSSHKit._QUEUE_ONLY
        @test DistSSHKit._route([c]) == (:queue, [c])
        # Queue does not steal `-v`. `go -v` is the version; `submit -v` is not.
        @test DistSSHKit._route([c, "-v"]) == (:queue, [c, "-v"])
    end
    for t in DistSSHKit._QUEUE_HELP_TOPICS
        for flag in ("-h", "--help", "help")
            @test DistSSHKit._route([flag, t]) == (:queue_help, [flag, t])
        end
    end
end

const _ROUTE_KINDS = (
    :version, :usage, :queue_help, :queue, :run, :no_command, :unknown,
)

function _route_shape_ok(got)::Bool
    got isa Tuple || return false
    length(got) == 2 || return false
    kind, payload = got
    kind isa Symbol || return false
    kind in _ROUTE_KINDS || return false
    if kind === :version
        return payload == String[]
    elseif kind === :usage
        return payload isa Int && payload in (0, 1)
    elseif kind in (:queue_help, :queue, :run)
        return payload isa Vector{String}
    else
        return payload isa String
    end
end

@testset "route shape" begin
    tokens = String[
        "go", "submit", "qhost", "qhost:H", "--remote-julia", "--queue-env",
        "--project", "--project=.", "--qhost", "-h", "--help", "-v",
        "x.jl", "", "ü", "--",
    ]
    bad = nothing
    function consider(a)
        got = try
            DistSSHKit._route(a)
        catch e
            return (a, e)
        end
        _route_shape_ok(got) && return nothing
        return (a, got)
    end
    bad = consider(String[])
    # Every short sequence. Longer ones are a seeded sample: 15^5 is large,
    # and the check is the shape, not one lucky input.
    if bad === nothing
        for n in 1:3
            for seq in Iterators.product(ntuple(_ -> tokens, n)...)
                bad = consider(String[seq...])
                bad === nothing || break
            end
            bad === nothing || break
        end
    end
    if bad === nothing
        rng = Xoshiro(20261015)
        for _ in 1:200
            n = rand(rng, 4:5)
            bad = consider(String[rand(rng, tokens) for _ in 1:n])
            bad === nothing || break
        end
    end
    @test bad === nothing
end

@testset "unhandled route" begin
    err = try
        DistSSHKit._apply_route(:not_a_route, "", String[])
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    if err isa ErrorException
        @test occursin("unhandled route: :not_a_route", err.msg)
    end
end
