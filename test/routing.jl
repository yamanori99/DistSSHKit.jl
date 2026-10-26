# `main` streams and the `_route` table. A forwarded page equals that
# owner's `main` under Kit's CLI entry, not a frozen sentence. A comment
# on a row says what that row records.

using Random

@testset "main" begin
    let (code, out, err) = _main_capture(String[])
        @test code == 1
        @test isempty(out)
        @test occursin("Usage", err)
        @test occursin("julia -m DistSSHKit <command>", err)
        @test occursin("submit", err)
    end
    let (code, out, err) = _main_capture(["foo"])
        @test code == 1
        @test isempty(out)
        @test occursin("Unknown subcommand: foo", err)
        @test occursin("submit", err)
    end
    # `help foo` is that same rejection. The named word is `foo`.
    @test _main_capture(["help", "foo"]) == _main_capture(["foo"])
    let (code, _, err) = _main_capture(["help", "map_echo.jl"])
        @test code == 1
        @test occursin("got \"map_echo.jl\"", err)
        @test occursin("does not infer go / ride / drive", err)
        @test !occursin("Unknown subcommand", err)
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
    # Root usage goes to stderr. That stream is the spec.
    let (code, out, err) = _main_capture(["--help"])
        @test code == 0
        @test isempty(out)
        @test occursin("Usage", err)
        @test occursin("progress", err)
        @test occursin("submit", err)
        @test occursin("qhost setup", err)
        @test !occursin("julia -m DistSSHQueue", err)
    end
    # Help words only: same root page, same stream, exit 0. No arguments stay 1.
    let root = _main_capture(["--help"])
        for a in (
                ["help", "--help"],
                ["-h", "--help"],
                ["help", "help"],
                ["--help", "help"],
                ["help", "-h", "--help"],
            )
            @test _main_capture(a) == root
        end
    end
    # Run's page. `main` is what Kit calls. `show_requirements` is not exported.
    _test_same_page(["go", "--help"], DistSSHRun.main)
    _test_same_page(["setup", "--help"], DistSSHRun.main)
    _test_same_page(["help", "go"], DistSSHRun.main, ["go", "--help"])
    _test_same_page(["help", "size"], DistSSHRun.main, ["size", "--help"])
    _test_same_page(["submit", "--help"], DistSSHQueue.main)
    _test_same_page(["help", "submit"], DistSSHQueue.main, ["submit", "--help"])
    # `submit <kind> --help` is the page before Queue's target check
    # (DistSSHQueue 0.9.10). The local-trial env stays so a 0.9.9 floor
    # still reaches that page.
    withenv(DistSSHQueue.LOCAL_QUEUE_ENV => "1") do
        for kind in string.(DistSSHQueue.KIT_EXECUTE_KINDS)
            _test_same_page(
                ["help", "submit", kind],
                DistSSHQueue.main,
                ["submit", kind, "--help"],
            )
        end
    end
    # Queue owns the topic heading. Render `main`; do not pin its words.
    _test_same_page(["--help", "client"], DistSSHQueue.main)
    # Kit drops the group word. The owner argv below is that stripped pair,
    # not a value read from `_route`. `cli_qhost_heading` still says `qhost`.
    _test_same_page(["qhost", "setup", "--help"], DistSSHQueue.main, ["setup", "--help"])
    _test_same_page(["help", "qhost", "setup"], DistSSHQueue.main, ["setup", "--help"])
    _test_same_page(["qhost:HOST", "submit", "--help"], DistSSHQueue.main)
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
        (["foo"], (:unknown, "foo")),
        # `-h` with an extra word is an unknown subcommand. The name is `-h`.
        (["-h", "foo"], (:unknown, "-h")),
        (["-h", "go"], (:unknown, "-h")),
        # Help words only are the root page. No arguments stay exit 1.
        (["help", "--help"], (:usage, 0)),
        (["-h", "--help"], (:usage, 0)),
        (["help", "help"], (:usage, 0)),
        (["--help", "help"], (:usage, 0)),
        (["help", "-h", "--help"], (:usage, 0)),
        # `help <verb>` is that verb's `--help`. A miss names the second word.
        (["help", "go"], (:run, ["go", "--help"])),
        (["help", "size"], (:run, ["size", "--help"])),
        (["help", "setup"], (:run, ["setup", "--help"])),
        (["help", "go", "--hosts", "parent"], (:run, ["go", "--help", "--hosts", "parent"])),
        (["help", "foo"], (:unknown, "foo")),
        (["help", "map_echo.jl"], (:no_command, "map_echo.jl")),
        (["help", "parent:2", "job.jl"], (:no_command, "parent:2")),
        # A help word or `qhost:` after `help` is not dropped.
        (["help", "help", "foo"], (:unknown, "help")),
        (["help", "qhost:HOST", "status"], (:queue, ["help", "qhost:HOST", "status"])),
        (["help", "qhost", "setup"], (:queue, ["setup", "--help"])),
        (["help", "qhost", "size"], (:queue, ["size", "--help"])),
        (["help", "qhost", "go"], (:queue, ["go", "--help"])),
        (["help", "submit"], (:queue, ["submit", "--help"])),
        (["help", "submit", "go"], (:queue, ["submit", "go", "--help"])),
        (["help", "submit", "go", "--x"], (:queue, ["submit", "go", "--help", "--x"])),
        (["help", "qhost", "submit", "go"], (:queue, ["submit", "go", "--help"])),
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
        @test DistSSHKit._route(["help", c]) == (:run, [c, "--help"])
    end
    for c in DistSSHKit._QUEUE_ONLY
        @test DistSSHKit._route([c]) == (:queue, [c])
        # Queue does not steal `-v`. `go -v` is the version; `submit -v` is not.
        @test DistSSHKit._route([c, "-v"]) == (:queue, [c, "-v"])
        @test DistSSHKit._route(["help", c]) == (:queue, [c, "--help"])
        @test DistSSHKit._route(["help", "qhost", c]) == (:queue, [c, "--help"])
    end
    for c in ("setup", "up", "size", "plan", "pool")
        @test DistSSHKit._route(["help", c]) == (:run, [c, "--help"])
        @test DistSSHKit._route(["help", "qhost", c]) == (:queue, [c, "--help"])
    end
    for kind in string.(DistSSHQueue.KIT_EXECUTE_KINDS)
        @test DistSSHKit._route(["help", "submit", kind]) ==
            (:queue, ["submit", kind, "--help"])
        @test DistSSHKit._route(["help", "qhost", "submit", kind]) ==
            (:queue, ["submit", kind, "--help"])
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
    # Lengths 1–3 are every sequence. A closure in `ntuple` is a JETLS
    # undef-global-var, so the three lengths are written out.
    if bad === nothing
        for a in tokens
            bad = consider([a])
            bad === nothing || break
        end
    end
    if bad === nothing
        for a in tokens, b in tokens
            bad = consider([a, b])
            bad === nothing || break
        end
    end
    if bad === nothing
        for a in tokens, b in tokens, c in tokens
            bad = consider([a, b, c])
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
