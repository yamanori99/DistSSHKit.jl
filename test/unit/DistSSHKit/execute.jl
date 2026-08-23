using Test

# Oracle: dispatcher only (plus detached `:go`, which is out-of-process).
# `execute!(:drive, …)` includes a driver into `Main` and lives in
# `integration/drive/execute.jl` (after `api.jl`, which is the first
# in-process `drive!` and owns the warn-overwrite check).

@testset "execute!" begin
    @testset "_remove_kit_pid_file" begin
        _with_tempdir() do d
            pid_path = joinpath(d, "kit.pid")
            write(pid_path, "4242")
            DistSSHKit._remove_kit_pid_file(99, d, nothing)
            @test isfile(pid_path)
            DistSSHKit._remove_kit_pid_file(4242, d, nothing)
            @test !isfile(pid_path)
        end
    end

    @testset "kit_result_from_dir" begin
        _with_tempdir() do d
            @test DistSSHKit.kit_result_from_dir(d) === nothing
            DistSSHKit._write_kit_result_file(DistSSHKit.KitRunResult(
                false, :drive, d, nothing, "drive", 42,
            ))
            got = DistSSHKit.kit_result_from_dir(d)
            @test got isa DistSSHKit.KitRunResult
            @test got.ok === false
            @test got.kind === :drive
            @test got.failed_step == "drive"
            @test got.exit_code == 42
            @test got.output_dir == d
            @test got.log_dir === nothing
            write(joinpath(d, "kit.result"), "not toml {")
            @test DistSSHKit.kit_result_from_dir(d) === nothing
        end
    end

    @testset "drive_host_status" begin
        @test DistSSHKit._probe_drive_host(Int[]) === :left
        @test DistSSHKit._probe_drive_host([999999]) === :left
        @test DistSSHKit._probe_drive_host([1]) === :alive
        DistSSHKit._clear_drive_host_worker_ids!()
        _with_tempdir() do d
            @test DistSSHKit.drive_host_status(d) == DistSSHKit.DriveHostStatus[]
            DistSSHKit._write_joined_drive_host_status!(["h1", "h2"], d, nothing)
            got = DistSSHKit.drive_host_status(d)
            @test length(got) == 2
            @test got[1].host == "h1"
            @test got[1].state === :joined
            @test got[1].last_seen === nothing
            DistSSHKit._register_drive_host_worker_ids!("h1", [1])
            DistSSHKit._register_drive_host_worker_ids!("h2", [999999])
            DistSSHKit._refresh_drive_host_status_file!(d, nothing; now=1.5)
            live = DistSSHKit.drive_host_status(d)
            by = Dict(r.host => r for r in live)
            @test by["h1"].state === :alive
            @test by["h1"].last_seen == 1.5
            @test by["h2"].state === :left
            DistSSHKit._mark_drive_hosts_collect_pending!(d, nothing; now=2.0)
            pending = DistSSHKit.drive_host_status(d)
            by2 = Dict(r.host => r for r in pending)
            @test by2["h1"].state === :collect_pending
            @test by2["h2"].state === :left
        end
        DistSSHKit._clear_drive_host_worker_ids!()
    end

    @testset "allocate_output_dir" begin
        _with_tempdir() do project
            d1 = DistSSHKit.allocate_output_dir(:go, "batch.jl"; project)
            @test isdir(d1)
            @test occursin(joinpath(".distsshkit", "go"), d1)
            @test startswith(basename(d1), "batch_")
            d2 = DistSSHKit.allocate_output_dir(:drive, "run.jl"; project, job_id="q1")
            @test isdir(d2)
            @test occursin(joinpath(".distsshkit", "drive"), d2)
            @test occursin("_q1", basename(d2))
            d3 = DistSSHKit.allocate_output_dir(:go, "batch.jl"; project)
            @test isdir(d3)
            @test d1 != d3
            err_kind = try
                DistSSHKit.allocate_output_dir(:pipeline, "x.jl"; project)
                nothing
            catch e
                e
            end
            @test err_kind isa ArgumentError
            err_id = try
                DistSSHKit.allocate_output_dir(:go, "x.jl"; project, job_id="bad id")
                nothing
            catch e
                e
            end
            @test err_id isa ArgumentError
        end
    end

    @testset "execute_detached_accepts" begin
        @test DistSSHKit.execute_detached_accepts(:quiet; kind=:go)
        @test DistSSHKit.execute_detached_accepts(:quiet; kind=:drive)
        @test DistSSHKit.execute_detached_accepts(:job_id; kind=:go)
        @test DistSSHKit.execute_detached_accepts(:job_id; kind=:drive)
        @test DistSSHKit.execute_detached_accepts(:output_dir; kind=:go)
        @test DistSSHKit.execute_detached_accepts(:output_dir; kind=:drive)
        @test DistSSHKit.execute_detached_accepts(:log_dir; kind=:drive)
        @test !DistSSHKit.execute_detached_accepts(:log_dir; kind=:go)
        @test !DistSSHKit.execute_detached_accepts(:plan; kind=:go)
        @test !DistSSHKit.execute_detached_accepts(:plan; kind=:drive)
        err = try
            DistSSHKit.execute_detached_accepts(:quiet; kind=:pipeline)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin(":go or :drive", sprint(showerror, err))
    end

    @testset "kind not :go / :drive" begin
        err = try
            DistSSHKit.execute!(:pipeline, "job.jl", String[])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin(":go or :drive", sprint(showerror, err))
    end

    @testset "detached rejects unknown / yes=false" begin
        err = try
            DistSSHKit.execute!(:go, "job.jl", ["local:1"]; detached=true, plan=nothing)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("does not accept keyword :plan", sprint(showerror, err))

        err2 = try
            DistSSHKit.execute!(:go, "job.jl", ["local:1"]; detached=true, yes=false)
            nothing
        catch e
            e
        end
        @test err2 isa ArgumentError
        @test occursin("yes=true", sprint(showerror, err2))

        err3 = try
            DistSSHKit.execute!(:go, "job.jl", ["local:1"]; detached=true, log_dir="x")
            nothing
        catch e
            e
        end
        @test err3 isa ArgumentError
        @test occursin(":log_dir", sprint(showerror, err3))
    end

    @testset ":go dispatch" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"ExecuteGo\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                write(joinpath(out, "args.txt"), join(ARGS, ","))
                """)
            result = DistSSHKit.execute!(
                :go,
                script,
                ["local:1"];
                project=proj,
                args=["8"],
                quiet=true,
                yes=true,
            )
            @test result isa DistSSHKit.KitRunResult
            @test result.kind === :go
            @test result.ok
            @test result.exit_code == 0
            @test result.output_dir !== nothing
            @test read(joinpath(result.output_dir, "parenthost", "args.txt"), String) == "8"
        end
    end

    @testset ":go detached" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"ExecuteGoDetached\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                write(joinpath(out, "args.txt"), join(ARGS, ","))
                """)
            mktemp() do _, out_io
                mktemp() do _, err_io
                    kp = DistSSHKit.execute!(
                        :go,
                        script,
                        ["local:1"];
                        detached=true,
                        project=proj,
                        args=["8"],
                        quiet=true,
                        stdout=out_io,
                        stderr=err_io,
                    )
                    pid_path = joinpath(kp.output_dir, "kit.pid")
                    if process_running(kp.process)
                        t0 = time()
                        while !isfile(pid_path) && process_running(kp.process) && (time() - t0) < 5
                            sleep(0.05)
                        end
                        if isfile(pid_path)
                            @test strip(read(pid_path, String)) == string(getpid(kp.process))
                        end
                    end
                    result = wait(kp)
                    flush(out_io)
                    flush(err_io)
                    @test kp isa DistSSHKit.KitProcess
                    @test kp.kind === :go
                    @test kp.log_dir === nothing
                    @test kp.output_dir !== nothing
                    @test result isa DistSSHKit.KitRunResult
                    @test result.kind === :go
                    @test result.ok
                    @test result.exit_code == 0
                    @test result.output_dir == kp.output_dir
                    @test result.log_dir === nothing
                    @test read(joinpath(result.output_dir, "parenthost", "args.txt"), String) == "8"
                    @test !isfile(pid_path)
                    @test !isfile(joinpath(result.output_dir, "kit.out"))
                    @test !isfile(joinpath(result.output_dir, "kit.err"))
                    recovered = DistSSHKit.kit_result_from_dir(result.output_dir)
                    @test recovered isa DistSSHKit.KitRunResult
                    @test recovered.ok
                    @test recovered.kind === :go
                    @test recovered.exit_code == 0
                    @test recovered.output_dir == result.output_dir
                    @test result.ok == recovered.ok
                    @test result.failed_step === recovered.failed_step
                end
            end
        end
    end

    @testset ":go detached job_id" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"ExecuteGoJobId\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                """)
            mktemp() do _, out_io
                mktemp() do _, err_io
                    kp = DistSSHKit.execute!(
                        :go,
                        script,
                        ["local:1"];
                        detached=true,
                        project=proj,
                        verbosity=:progress,
                        job_id="q-1",
                        stdout=out_io,
                        stderr=err_io,
                    )
                    result = wait(kp)
                    @test result.ok
                    pid_path = joinpath(result.output_dir, "kit.pid")
                    @test !isfile(pid_path)
                    @test isfile(joinpath(result.output_dir, "kit.job"))
                    @test strip(read(joinpath(result.output_dir, "kit.job"), String)) == "q-1"
                    log_files = filter(f -> endswith(f, ".log"), readdir(result.output_dir))
                    @test !isempty(log_files)
                    log_body = read(joinpath(result.output_dir, first(log_files)), String)
                    @test occursin("job=q-1", log_body)
                end
            end
        end
    end

    @testset ":go detached default stdio files" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"ExecuteGoStdio\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                """)
            kp = DistSSHKit.execute!(
                :go,
                script,
                ["parenthost:1"];
                detached=true,
                project=proj,
                quiet=true,
            )
            result = wait(kp)
            @test result.ok
            @test isfile(joinpath(result.output_dir, "kit.out"))
            @test isfile(joinpath(result.output_dir, "kit.err"))
        end
    end

    @testset "job_id charset / kit_job_eval_arg" begin
        withenv("DISTSSHKIT_JOB_ID" => nothing) do
            @test DistSSHKit.resolved_kit_job_id() === nothing
        end
        @test occursin("distsshkit-job:q-1", DistSSHKit.kit_job_eval_arg("q-1"))
        err = try
            DistSSHKit._parse_kit_job_id("has space")
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
    end

    @testset "wait timeout hung" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"WaitHung\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                sleep(60)
                """)
            kp = DistSSHKit.execute!(
                :go,
                script,
                ["parenthost:1"];
                detached=true,
                project=proj,
                quiet=true,
            )
            hung = wait(kp; timeout=0.4)
            @test hung.ok === false
            @test hung.failed_step == "hung"
            @test hung.exit_code == 124
            @test process_running(kp.process)
            killed = DistSSHKit.terminate!(kp; grace=2)
            @test !process_running(kp.process)
            @test killed isa DistSSHKit.KitRunResult
        end
    end

    @testset "terminate! detached go" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"TerminateGo\"\n")
            script = joinpath(proj, "job.jl")
            write(script, """
                out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
                mkpath(out)
                sleep(60)
                """)
            mktemp() do _, out_io
                mktemp() do _, err_io
                    kp = DistSSHKit.execute!(
                        :go,
                        script,
                        ["parenthost:1"];
                        detached=true,
                        project=proj,
                        verbosity=:progress,
                        job_id="t-1",
                        stdout=out_io,
                        stderr=err_io,
                    )
                    result = DistSSHKit.terminate!(kp; grace=2)
                    @test result isa DistSSHKit.KitRunResult
                    @test !process_running(kp.process)
                    @test result.kind === :go
                end
            end
        end
    end

    @testset "terminate_run! missing pid" begin
        _with_tempdir() do d
            r = DistSSHKit.terminate_run!(d; grace=0)
            @test r isa DistSSHKit.KitRunResult
            @test r.ok === false
            @test r.failed_step == "terminated"
            @test r.kind === :go
        end
    end
end
