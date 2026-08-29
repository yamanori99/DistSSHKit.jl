using Test

# Oracle: local `git` CLI for push/pull, and `git_sync` stopping before remotes
# when local push/pull fails. Remote `git pull` uses raw `ssh` (not the setup
# fake); unreachable hosts only. Real remote git is SSH E2E.

@testset "setup git" begin
    function _git_ident!(dir)
        run(pipeline(`git -C $dir config user.email "test@example.com"`; stdout=devnull, stderr=devnull))
        run(pipeline(`git -C $dir config user.name "Test"`; stdout=devnull, stderr=devnull))
        return nothing
    end

    function _init_commit!(dir)
        run(pipeline(`git -C $dir init -q`; stdout=devnull, stderr=devnull))
        _git_ident!(dir)
        write(joinpath(dir, "f.txt"), "hi\n")
        run(pipeline(`git -C $dir add f.txt`; stdout=devnull, stderr=devnull))
        run(pipeline(`git -C $dir commit -q -m init`; stdout=devnull, stderr=devnull))
        return nothing
    end

    @testset "resolve_clone_url" begin
        @test DistSSHKit.resolve_clone_url(
            "https://github.com/org/App.jl.git",
            "/unused",
        ) == "git@github.com:org/App.jl.git"
        _with_tempdir() do tmp
            @test_throws ErrorException DistSSHKit.resolve_clone_url(nothing, tmp; surface=:cli)
            @test_throws ErrorException DistSSHKit.resolve_clone_url("", tmp; surface=:api)
        end
    end

    Sys.which("git") === nothing && return

    @testset "push / local pull" begin
        _with_tempdir() do tmp
            work = joinpath(tmp, "work")
            mkpath(work)
            _init_commit!(work)
            @test DistSSHKit._git_remote_url(work) == "<repo_url>"
            @test !DistSSHKit.git_push_project!(work)
            @test !DistSSHKit.git_pull_local_project!(work)

            bare = joinpath(tmp, "origin.git")
            run(pipeline(`git init -q --bare $bare`; stdout=devnull, stderr=devnull))
            run(pipeline(`git -C $work remote add origin $bare`; stdout=devnull, stderr=devnull))
            @test DistSSHKit._git_remote_url(work) == bare
            # `git push` with no upstream tracking fails.
            @test !DistSSHKit.git_push_project!(work)
            run(pipeline(`git -C $work push -q -u origin HEAD`; stdout=devnull, stderr=devnull))
            @test DistSSHKit.git_push_project!(work)
            @test DistSSHKit.git_pull_local_project!(work)
        end
    end

    @testset "git_sync stops on local failure" begin
        _apply_quiet_setup_session!()
        _with_tempdir() do tmp
            work = joinpath(tmp, "work")
            mkpath(work)
            _init_commit!(work)
            out, raw = _capture_stdio() do _, _
                DistSSHKit.git_sync_project_to_hosts!(
                    ["192.0.2.1"], work, "~/App.jl";
                    do_push=true, do_pull=true, do_local_pull=false,
                )
            end
            @test !raw.ok
            @test isempty(raw.host_results)
            @test occursin("Push failed.", out)

            raw_pull = DistSSHKit.git_sync_project_to_hosts!(
                ["192.0.2.1"], work, "~/App.jl";
                do_push=false, do_pull=true, do_local_pull=true,
            )
            @test !raw_pull.ok
            @test isempty(raw_pull.host_results)
        end
    end

    @testset "git_sync confirm abort" begin
        withenv("DISTSSHKIT_YES" => nothing) do
            prev_ni = DistSSHKit.kit_noninteractive()
            DistSSHKit.set_kit_noninteractive!(false)
            try
                _with_tempdir() do tmp
                    work = joinpath(tmp, "work")
                    mkpath(work)
                    _init_commit!(work)
                    for v in (:quiet, :progress, :verbose)
                        with_kit_verbosity(v) do
                            out, raw = _capture_stdio() do stdin_io, _
                                println(stdin_io, "n")
                                flush(stdin_io)
                                seekstart(stdin_io)
                                DistSSHKit.git_sync_project_to_hosts!(
                                    ["host1"], work, "~/App.jl";
                                    do_push=true, do_pull=true, do_local_pull=false,
                                )
                            end
                            @test !raw.ok
                            @test raw.cancelled
                            @test isempty(raw.host_results)
                            @test occursin("Cancelled.", out)
                            @test occursin("Proceed?", out)
                            @test occursin("git push", out)
                        end
                    end
                    _, raw_skip = _capture_stdio() do _, _
                        DistSSHKit.git_sync_project_to_hosts!(
                            ["192.0.2.1"], work, "~/App.jl";
                            do_push=true, do_pull=false, do_local_pull=false, confirm=false,
                        )
                    end
                    @test !raw_skip.ok
                    @test !raw_skip.cancelled
                end
            finally
                DistSSHKit.set_kit_noninteractive!(prev_ni)
            end
        end
    end

    @testset "remote pull: unreachable host" begin
        Sys.which("ssh") === nothing && return
        _apply_quiet_setup_session!()
        withenv("DISTRIBUTED_SSH_OPTS" => "-o BatchMode=yes -o ConnectTimeout=1") do
            @test !DistSSHKit.git_pull_remote_host!("192.0.2.1", "~/App.jl")
            _with_tempdir() do tmp
                work = joinpath(tmp, "work")
                mkpath(work)
                _init_commit!(work)
                raw = DistSSHKit.git_sync_project_to_hosts!(
                    ["192.0.2.1", "192.0.2.2"], work, "~/App.jl";
                    do_push=false, do_pull=true, do_local_pull=false,
                )
                @test !raw.ok
                @test length(raw.host_results) == 1
                @test raw.host_results[1].host == "192.0.2.1"
                @test !raw.host_results[1].ok
            end
        end
    end
end
