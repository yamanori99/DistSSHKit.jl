using Test

@testset "explain surfaces" begin
    @test DistSSHKit.join_explained_message("a", nothing) == "a"
    @test DistSSHKit.join_explained_message("a", "b") == "a\nb"

    @testset "surface / kind contracts" begin
        @test_throws ArgumentError DistSSHKit._normalize_hint_surface(:nope)
        @test_throws ArgumentError DistSSHKit.explain_no_hosts(; kind=:drive)
        cli_size = DistSSHKit.explain_no_hosts(; surface=:cli, kind=:size)
        @test occursin("size --help", cli_size)
        cli_collect = DistSSHKit.explain_no_hosts(; surface=:cli, kind=:collect)
        @test occursin("--collect-missing", cli_collect)
    end

    @testset "script not found" begin
        _with_tempdir() do tmp::String
            missing = joinpath(tmp, "nope.jl")
            msg = DistSSHKit.explain_script_not_found(missing, tmp; surface=:api)
            @test occursin("Script not found", msg)
            @test occursin(missing, msg)
            @test !occursin("install_demos", msg)
            demo = joinpath(tmp, "demos", "with_kit", "rho_sweep.jl")
            demo_msg = DistSSHKit.explain_script_not_found(demo, tmp; surface=:api)
            @test occursin("install_demos", demo_msg)
        end
    end

    @testset "hosts file" begin
        msg = DistSSHKit.explain_hosts_file_not_found("/no/hosts"; surface=:cli)
        @test occursin("hosts file not found", msg)
        @test occursin("--hosts-file", msg)
        msg_api = DistSSHKit.explain_hosts_file_not_found("/no/hosts"; surface=:api)
        @test occursin("hosts_file=", msg_api)

        empty_cli = DistSSHKit.explain_hosts_file_empty("/empty"; surface=:cli)
        @test occursin("command line", empty_cli)
        empty_api = DistSSHKit.explain_hosts_file_empty("/empty"; surface=:api)
        @test occursin("workers=", empty_api)
    end

    @testset "no hosts" begin
        @test occursin("workers=", DistSSHKit.explain_no_hosts(; surface=:api, kind=:ssh))
        @test occursin("--hosts-file", DistSSHKit.explain_no_hosts(; surface=:cli, kind=:ssh))
        @test occursin("collect!", DistSSHKit.explain_no_hosts(; surface=:api, kind=:collect))
        @test occursin("size_plan", DistSSHKit.explain_no_hosts(; surface=:api, kind=:size))
    end

    @testset "clone / probe / driver" begin
        @test occursin("repo=", DistSSHKit.explain_clone_repo_required(; surface=:api))
        @test occursin("--repo", DistSSHKit.explain_clone_repo_required(; surface=:cli))
        @test occursin("--repo", DistSSHKit.explain_clone_origin_missing(; surface=:cli))
        @test occursin("repo=", DistSSHKit.explain_clone_origin_missing(; surface=:api))
        @test occursin("--probe", DistSSHKit.explain_size_probe_not_found("x.jl"; surface=:cli))
        @test occursin("probe=", DistSSHKit.explain_size_probe_not_found("x.jl"; surface=:api))
        @test occursin("driver=", DistSSHKit.explain_pipeline_driver_missing(; surface=:api))
    end

    @testset "session wiring" begin
        _with_tempdir() do tmp::String
            session = DistSSHKit.KitSession(project=tmp, workers=String[])
            @test DistSSHKit.hint_surface(session) === :api
            @test session.cli_session.hint_surface === :api

            err = try
                DistSSHKit.sync!(session)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("workers=", sprint(showerror, err))
            @test occursin("Hint:", sprint(showerror, err))

            @test DistSSHKit.KitCliSession().hint_surface === :cli
        end
    end

    @testset "hosts file throws" begin
        _with_tempdir() do tmp::String
            missing = joinpath(tmp, "no-hosts.txt")
            err = try
                DistSSHKit.read_hosts_file_lines(missing; surface=:api)
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("hosts_file=", sprint(showerror, err))

            empty = joinpath(tmp, "empty.txt")
            write(empty, "# only comments\n\n")
            err2 = try
                DistSSHKit.read_hosts_file_lines(empty; surface=:cli)
                nothing
            catch e
                e
            end
            @test err2 isa ArgumentError
            @test occursin("command line", sprint(showerror, err2))
        end
    end
end
