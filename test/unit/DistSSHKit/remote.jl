using Test

@testset "remote" begin
    @test DistSSHKit.ssh_addprocs_machine("dev@host1") == "dev@host1"
    @test DistSSHKit.ssh_addprocs_machine("  alice@h  ") == "alice@h"

    @test DistSSHKit.normalize_git_clone_url("https://github.com/org/App.jl.git") ==
        "git@github.com:org/App.jl.git"
    @test DistSSHKit.normalize_git_clone_url("git@github.com:org/App.jl.git") ==
        "git@github.com:org/App.jl.git"

    @test DistSSHKit.default_remote_project_path("/Users/z/GitHub/MyApp.jl") ==
        joinpath("~", "GitHub", "MyApp.jl")

    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => nothing) do
        @test DistSSHKit.resolve_remote_project_root("/Users/z/GitHub/MyApp.jl") ==
            joinpath("~", "GitHub", "MyApp.jl")
    end
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/shared/MyApp.jl") do
        @test DistSSHKit.resolve_remote_project_root("/Users/z/GitHub/MyApp.jl") ==
            "/Volumes/shared/MyApp.jl"
    end
    @test DistSSHKit.resolve_remote_project_root(
            "/Users/z/GitHub/MyApp.jl";
            cli_override="~/work/MyApp.jl",
        ) == "~/work/MyApp.jl"
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/shared/MyApp.jl") do
        @test DistSSHKit.resolve_remote_project_root(
                "/Users/z/GitHub/MyApp.jl";
                cli_override="~/work/MyApp.jl",
            ) == "~/work/MyApp.jl"
    end

    @test DistSSHKit.local_dir_from_remote_mirror(
            "/Volumes/r/MyRepo/data/sweep/slug/20260101_120000",
            "/Volumes/r/MyRepo",
            "/Users/z/MyRepo",
        ) == joinpath("/Users/z/MyRepo", "data", "sweep", "slug", "20260101_120000") |> abspath
    @test_throws ArgumentError DistSSHKit.local_dir_from_remote_mirror(
        "~/r/MyRepo/data",
        "~/r/MyRepo",
        "/Users/z/MyRepo",
    )
    @test_throws ArgumentError DistSSHKit.local_dir_from_remote_mirror(
        "/Volumes/r/MyRepo/data",
        "~/r/MyRepo",
        "/Users/z/MyRepo",
    )

    @test DistSSHKit.resolve_remote_abs_path_on_host("host", "/data/MyRepo") == "/data/MyRepo"
    # Public path helpers cover the ~ case; avoid asserting on private shell snippets.

    @test DistSSHKit.remote_path_for_ssh_collect(
            "/Users/z/MyRepo/data/out",
            "/Users/z/MyRepo",
        ) == joinpath("~", "z", "MyRepo", "data", "out")
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/z/clone/MyRepo") do
        @test DistSSHKit.remote_path_for_ssh_collect(
                "/Users/z/MyRepo/data/sweep/x/ts",
                "/Users/z/MyRepo",
            ) == joinpath("/Volumes/z/clone/MyRepo", "data", "sweep", "x", "ts") |> abspath
    end
    withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "~/work/MyRepo") do
        @test DistSSHKit.remote_path_for_ssh_collect(
                "/Users/z/MyRepo/demos/with_kit",
                "/Users/z/MyRepo",
            ) == joinpath("~/work/MyRepo", "demos", "with_kit")
    end

    @testset "ensure_remote_abs_path" begin
        @test DistSSHKit.ensure_remote_abs_path("host", "/home/dev/App") == "/home/dev/App"
        @test DistSSHKit.ensure_remote_abs_path("host", "") === nothing
        @test DistSSHKit.ensure_remote_abs_path("host", "   ") === nothing
    end

    @testset "resolve_host_path_abs" begin
        _with_tempdir() do tmp
            p = DistSSHKit.canonical_local_path(tmp)
            @test DistSSHKit.resolve_host_project_abs("parent", p) == p
            withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/z/clone/MyRepo") do
                @test DistSSHKit.resolve_host_project_abs("host", p) == "/Volumes/z/clone/MyRepo"
            end
        end
    end

    withenv("DISTRIBUTED_SSH_OPTS" => nothing) do
        opts = DistSSHKit.build_ssh_opts()
        @test "-o" in opts
        @test "BatchMode=yes" in opts
        @test "RequestTTY=no" in opts
        @test DistSSHKit.ssh_opts() == String.(opts)
        tty = DistSSHKit.ssh_opts(; request_tty=true)
        @test !("RequestTTY=no" in tty)
        @test "BatchMode=yes" in tty
        @test DistSSHKit.build_ssh_opts(; request_tty=true) == tty
        @test DistSSHKit.ssh_opts(; request_tty=false) == DistSSHKit.ssh_opts()
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-o Foo=bar -o Baz=qux") do
        @test DistSSHKit.build_ssh_opts() == ["-o", "Foo=bar", "-o", "Baz=qux"]
        @test DistSSHKit.ssh_opts() == ["-o", "Foo=bar", "-o", "Baz=qux"]
        @test DistSSHKit.ssh_opts(; request_tty=true) == ["-o", "Foo=bar", "-o", "Baz=qux"]
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-F /tmp/ssh_config") do
        @test DistSSHKit.ssh_opts() == ["-F", "/tmp/ssh_config"]
        @test DistSSHKit.ssh_opts(; request_tty=true) == ["-F", "/tmp/ssh_config"]
    end

    let r = DistSSHKit.get_local_resources()
        @test r.total_gb > 0
        @test r.nproc >= 1
    end

    _with_tempdir() do tmp
        d = tmp
        @test DistSSHKit.get_local_git_hash(d) === nothing
        @test DistSSHKit.clone_url_from_local_origin(d) === nothing
        @test DistSSHKit.local_git_clean(d)

        run(Cmd(["git", "-C", d, "init", "-q"]))
        run(Cmd(["git", "-C", d, "config", "user.email", "test@example.com"]))
        run(Cmd(["git", "-C", d, "config", "user.name", "Test"]))
        @test DistSSHKit.local_git_clean(d)

        write(joinpath(d, "f.txt"), "hi")
        @test !DistSSHKit.local_git_clean(d)

        run(Cmd(["git", "-C", d, "add", "f.txt"]))
        run(Cmd(["git", "-C", d, "commit", "-q", "-m", "init"]))
        @test DistSSHKit.local_git_clean(d)

        write(joinpath(d, "f.txt"), "hi2")
        @test !DistSSHKit.local_git_clean(d)

        full = DistSSHKit.get_local_git_hash(d)
        @test full isa String
        full isa String || error("expected full git hash")
        @test length(full) == 40
        short = DistSSHKit.get_local_git_hash(d; short=8)
        @test short isa String
        short isa String || error("expected short git hash")
        @test length(short) == 8
        @test startswith(full, short)

        run(Cmd(["git", "-C", d, "remote", "add", "origin", "https://github.com/org/App.jl.git"]))
        @test DistSSHKit.clone_url_from_local_origin(d) == "git@github.com:org/App.jl.git"
    end

    @test DistSSHKit.parse_julia_version("julia version 1.12.6") == v"1.12.6"
    @test DistSSHKit.parse_julia_version("julia version 1.9.0-DEV") == v"1.9.0"
    @test DistSSHKit.parse_julia_version("julia version 1.13.0-beta1") == v"1.13.0"
    @test DistSSHKit.parse_julia_version("") === nothing
    @test DistSSHKit.parse_julia_version("not julia at all") === nothing

    @testset "remote_julia_candidates" begin
        darwin = DistSSHKit.remote_julia_candidates("Darwin")
        @test darwin[1] == raw"$HOME/.juliaup/bin/julia"
        @test "/opt/homebrew/bin/julia" in darwin
        @test "/usr/local/bin/julia" in darwin
        linux = DistSSHKit.remote_julia_candidates("Linux")
        @test linux[1] == raw"$HOME/.juliaup/bin/julia"
        @test "/usr/bin/julia" in linux
        @test !("/opt/homebrew/bin/julia" in linux)
    end

    @testset "resolve_controller_julia" begin
        p = DistSSHKit.resolve_controller_julia("auto")
        @test isabspath(p)
        @test isfile(p)
        @test DistSSHKit.resolve_controller_julia(nothing) == p
        @test DistSSHKit.resolve_controller_julia(p) == p
        @test_throws ArgumentError DistSSHKit.resolve_controller_julia("/no/such/julia")
    end

    @testset "_remote_shell_path_word" begin
        @test DistSSHKit._remote_shell_path_word("~/proj") == "~/proj"
        spaced = "/opt/Julia 1.12/bin/julia"
        @test DistSSHKit._remote_shell_path_word(spaced) == Base.shell_escape(spaced)
        meta = "/tmp/j;rm -rf /"
        @test DistSSHKit._remote_shell_path_word(meta) == Base.shell_escape(meta)
        @test DistSSHKit._remote_shell_path_word(meta) != meta
    end

    # Compat: ordinary remote roots keep the same shell text after quoting via the helper.
    @testset "compat remote git shells" begin
        tilde = "~/App.jl"
        abs = "/opt/App.jl"
        pq_abs = DistSSHKit._remote_shell_path_word(abs)
        @test DistSSHKit._git_pull_remote_inner(tilde) == "cd ~/App.jl && git pull"
        @test DistSSHKit._git_pull_remote_inner(abs) == "cd $pq_abs && git pull"
        @test DistSSHKit._remote_git_hash_inner(tilde) == "cd ~/App.jl && git rev-parse HEAD"
        @test DistSSHKit._remote_git_hash_inner(abs) == "git -C $pq_abs rev-parse HEAD"
        @test DistSSHKit._remote_git_hash_inner(abs; short=8) == "git -C $pq_abs rev-parse --short=8 HEAD"
        @test pq_abs == abs
    end

    @testset "detect_julia_path cache" begin
        empty!(DistSSHKit._DETECT_JULIA_PATH_CACHE)
        try
            @test DistSSHKit.detect_julia_path("") === nothing
            @test !haskey(DistSSHKit._DETECT_JULIA_PATH_CACHE, "")
            @test DistSSHKit.detect_julia_path("no-such-host.invalid") === nothing
            @test DistSSHKit._DETECT_JULIA_PATH_CACHE["no-such-host.invalid"] === nothing
            DistSSHKit._DETECT_JULIA_PATH_CACHE["cache-hit.host"] = "/opt/julia"
            @test DistSSHKit.detect_julia_path("cache-hit.host") == "/opt/julia"
        finally
            empty!(DistSSHKit._DETECT_JULIA_PATH_CACHE)
        end
    end

    @test DistSSHKit.get_remote_julia_version("no-such-host.invalid", "/usr/bin/julia") === nothing
    @test DistSSHKit.detect_julia_path("no-such-host.invalid") === nothing
    @test DistSSHKit.resolve_remote_julia("no-such-host.invalid", "auto") === nothing

    @testset "run_on_host remote sh" begin
        sh = DistSSHKit._run_on_host_remote_sh(["-e", "1"]; detect=true)
        @test occursin("uname -s", sh)
        @test occursin("exec", sh)
        @test occursin(raw"$HOME/.juliaup/bin/julia", sh)
        @test occursin("/opt/homebrew/bin/julia", sh)
        @test occursin("-e", sh)
        @test DistSSHKit._remote_argv_sh(["-e", "exit(3)"]) == "'-e' 'exit(3)'"
        @test DistSSHKit._remote_sh_quote("a'b") == raw"'a'\''b'"
        expl = DistSSHKit._run_on_host_remote_sh(["--version"]; julia="/opt/julia", detect=false)
        @test occursin("/opt/julia", expl)
        @test occursin("exec", expl)
        @test !occursin("uname", expl)
        err = try
            DistSSHKit._run_on_host_remote_sh(String[]; detect=false, julia=nothing)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        err2 = try
            DistSSHKit.run_on_host("", ["--version"])
            nothing
        catch e
            e
        end
        @test err2 isa ArgumentError
        let p = redirect_stderr(devnull) do
                DistSSHKit.run_on_host("no-such-host.invalid", ["--version"])
            end
            @test p isa Base.Process
            @test p.exitcode != 0
        end
    end

    @test !DistSSHKit._remote_ssh_ok("no-such-host.invalid")
end
