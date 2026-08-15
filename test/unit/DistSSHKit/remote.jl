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
        _with_tempdir() do tmp::String
            p = DistSSHKit.canonical_local_path(tmp)
            @test DistSSHKit.resolve_host_project_abs("localhost", p) == p
            withenv("DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/Volumes/z/clone/MyRepo") do
                @test DistSSHKit.resolve_host_project_abs("host", p) == "/Volumes/z/clone/MyRepo"
            end
        end
    end

    withenv("DISTRIBUTED_SSH_OPTS" => nothing) do
        opts = DistSSHKit.build_ssh_opts()
        @test "-o" in opts
        @test "BatchMode=yes" in opts
        @test DistSSHKit.ssh_opts() == String.(opts)
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-o Foo=bar -o Baz=qux") do
        @test DistSSHKit.build_ssh_opts() == ["-o", "Foo=bar", "-o", "Baz=qux"]
        @test DistSSHKit.ssh_opts() == ["-o", "Foo=bar", "-o", "Baz=qux"]
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-F /tmp/ssh_config") do
        @test DistSSHKit.ssh_opts() == ["-F", "/tmp/ssh_config"]
    end

    let r = DistSSHKit.get_local_resources()
        @test r.total_gb > 0
        @test r.nproc >= 1
    end

    _with_tempdir() do tmp::String
        d = abspath(string(tmp))
        @test DistSSHKit.get_local_git_hash(d) === nothing
        @test DistSSHKit.clone_url_from_local_origin(d) === nothing
        @test DistSSHKit.local_git_clean(d) == true

        run(Cmd(["git", "-C", d, "init", "-q"]))
        run(Cmd(["git", "-C", d, "config", "user.email", "test@example.com"]))
        run(Cmd(["git", "-C", d, "config", "user.name", "Test"]))
        @test DistSSHKit.local_git_clean(d) == true

        write(joinpath(d, "f.txt"), "hi")
        @test DistSSHKit.local_git_clean(d) == false

        run(Cmd(["git", "-C", d, "add", "f.txt"]))
        run(Cmd(["git", "-C", d, "commit", "-q", "-m", "init"]))
        @test DistSSHKit.local_git_clean(d) == true

        write(joinpath(d, "f.txt"), "hi2")
        @test DistSSHKit.local_git_clean(d) == false

        full = DistSSHKit.get_local_git_hash(d)
        @test full isa String
        full = full::String
        @test length(full) == 40
        short = DistSSHKit.get_local_git_hash(d; short=8)
        @test short isa String
        short = short::String
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

    @test DistSSHKit.get_remote_julia_version("no-such-host.invalid", "/usr/bin/julia") === nothing
    @test DistSSHKit.detect_julia_path("no-such-host.invalid") === nothing
    @test DistSSHKit.resolve_remote_julia("no-such-host.invalid", "auto") === nothing

    @test DistSSHKit._remote_ssh_ok("no-such-host.invalid") == false
end
