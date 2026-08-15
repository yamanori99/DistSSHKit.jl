using Test

@testset "DistSSHKit module" begin
    _with_tempdir() do tmp
        d = abspath(string(tmp))
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
end
