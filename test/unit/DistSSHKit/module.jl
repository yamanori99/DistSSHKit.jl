using Test

@testset "DistSSHKit module" begin
    _with_tempdir() do tmp
        d = tmp
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
        write(joinpath(d, "Project.toml"), "name = \"Foo\"\n")
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
        write(joinpath(d, "Project.toml"), "name = \"Foo\"\nversion = \"1.2.3\"\n")
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) == v"1.2.3"
        write(joinpath(d, "Project.toml"), "version = \"not-a-version\"\n")
        @test DistSSHKit._project_toml_version(joinpath(d, "Project.toml")) === nothing
    end

    @test DistSSHKit.dist_ssh_kit_version() isa VersionNumber
    @test DistSSHKit.dist_ssh_kit_version() != v"0.0.0"

    # Public surface: sizing is `size!`; argv `go` / `drive` are unexported.
    ns = names(DistSSHKit)
    @test :size! in ns && :go! in ns && :drive! in ns
    @test :KitRunResult in ns && :kit_run_result in ns && :report_run_errors in ns
    @test :execute! in ns && :KitProcess in ns && :kit_result_from_dir in ns
    @test :execute_detached_accepts in ns && :kit_pid_alive in ns
    @test :parse_worker_tokens in ns && :ParsedWorkerTokens in ns
    @test :worker_tokens_fully_specified in ns && :remote_hosts_from_tokens in ns
    @test :worker_plan_from_tokens in ns
    @test :split_worker_token in ns && :is_local_host_name in ns && :host_tokens in ns
    @test :size_plan ∉ ns && :go ∉ ns && :drive ∉ ns
    @test isdefined(DistSSHKit, :go) && isdefined(DistSSHKit, :drive)
    @test !isdefined(DistSSHKit, :size_plan)

    let fixture = _fixture("cli_echo_args.jl")
        mktemp() do args_file, _
            withenv(
                "DISTRIBUTED_PROJECT_ROOT" => "/override",
                "_DISTSSHKIT_TEST_ARGS_FILE" => args_file,
            ) do
                empty!(ARGS)
                append!(ARGS, ["--local", "2", "job.jl"])
                @test DistSSHKit._run_kit_cli_script(fixture, ARGS) == 0
                @test readlines(args_file) == ["--local", "2", "job.jl"]
            end
        end

        _with_tempdir() do tmp
            mktemp() do args_file, _
                withenv(
                    "DISTRIBUTED_PROJECT_ROOT" => nothing,
                    "_DISTSSHKIT_TEST_ARGS_FILE" => args_file,
                ) do
                    cd(tmp) do
                        empty!(ARGS)
                        @test DistSSHKit._run_kit_cli_script(fixture, ["probe"]) == 0
                        @test realpath(ENV["DISTRIBUTED_PROJECT_ROOT"]) == realpath(tmp)
                        @test readlines(args_file) == ["probe"]
                    end
                end
            end
        end
    end

    @testset "script arg prelude" begin
        withenv("DISTSSHKIT_SCRIPT_ARG_PRELUDE" => "alpha\n\nbeta") do
            @test DistSSHKit._merge_script_arg_prelude(["job.jl"]) == ["job.jl", "alpha", "beta"]
        end
        @test get(ENV, "DISTSSHKIT_SCRIPT_ARG_PRELUDE", nothing) === nothing
    end
end
