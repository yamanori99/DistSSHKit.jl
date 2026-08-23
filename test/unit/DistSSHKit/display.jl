using Test

@testset "display" begin
    @testset "kit_pid_alive" begin
        @test DistSSHKit.kit_pid_alive(0) === false
        @test DistSSHKit.kit_pid_alive(-1) === false
        if Sys.isunix()
            @test DistSSHKit.kit_pid_alive(getpid()) === true
            @test DistSSHKit.kit_process_start_key(getpid()) isa String
        end
    end

    @testset "paths" begin
        _with_tempdir() do tmp
            rel = joinpath(tmp, "nested")
            mkpath(rel)
            @test DistSSHKit.canonical_local_path(rel) == abspath(rel)
            @test DistSSHKit.canonical_local_path(joinpath("~", ".ssh")) ==
                abspath(expanduser(joinpath("~", ".ssh")))
        end

        let home = expanduser("~")
            @test DistSSHKit.short_path(joinpath(home, "foo", "bar")) == joinpath("~", "foo", "bar")
        end

        _with_tempdir() do tmp
            d = tmp
            nested = joinpath(d, "a", "b.txt")
            mkpath(dirname(nested))
            write(nested, "")
            @test DistSSHKit.display_path(nested, d) == joinpath("a", "b.txt")
        end
    end

    @testset "project layout" begin
        # Standalone kit vs host-app embedding (the two layouts that matter).
        withenv("DISTRIBUTED_PROJECT_ROOT" => nothing) do
        _with_tempdir() do tmp
            d = tmp
            write(joinpath(d, "Project.toml"), "name = \"DistSSHKit\"\n")
            src = joinpath(d, "src")
            mkpath(src)
            @test DistSSHKit.kit_project_root(src) == d
            cd(d) do
                @test DistSSHKit.cli_project_root(src) == realpath(d)
            end
            @test DistSSHKit._cli_job_root(d, d) == d
            @test DistSSHKit.resolve_pkg_project_dir(d) == d
        end
        withenv("DISTRIBUTED_PROJECT_ROOT" => "/override/root") do
            @test DistSSHKit.cli_project_root("/unused") == "/override/root"
        end
        _with_tempdir() do tmp
            d = tmp
            app = joinpath(d, "MyApp")
            kit = joinpath(app, "DistSSHKit")
            scripts = joinpath(app, "scripts", "jobs")
            mkpath(scripts)
            mkpath(joinpath(kit, "src"))
            write(joinpath(app, "Project.toml"), "name = \"MyApp\"\n")
            write(joinpath(kit, "Project.toml"), "name = \"DistSSHKit\"\n")
            @test DistSSHKit.kit_project_root(joinpath(kit, "src")) == app
            @test DistSSHKit.cli_project_root(joinpath(kit, "src")) == app
            @test DistSSHKit.resolve_pkg_project_dir(scripts) == app
        end
        _with_tempdir() do tmp
            d = tmp
            @test DistSSHKit.project_package_name(d) === nothing
            write(joinpath(d, "Project.toml"), "name = \"FooBar\"\n")
            @test DistSSHKit.project_package_name(d) == "FooBar"
        end
        _with_tempdir() do tmp
            d = tmp
            write(joinpath(d, "Project.toml"), "name = \"DistSSHKit\"\n")
            cli = joinpath(d, "src", "cli")
            mkpath(cli)
            @test DistSSHKit.kit_project_root(cli) == d
            @test DistSSHKit.cli_project_disp(d, DistSSHKit.canonical_local_path(d)) ==
                basename(abspath(d))
        end
        @test DistSSHKit._path_is_under("/a/b/c", "/a/b")
        @test DistSSHKit._path_is_under("/a/b", "/a/b")
        @test !DistSSHKit._path_is_under("/a/bother", "/a/b")
        # Loaded DistSSHKit is not the host Project.toml (Pkg.add / apps).
        _with_tempdir() do tmp
            d = tmp
            pkg = joinpath(d, "packages", "DistSSHKit", "XXXX")
            mkpath(joinpath(pkg, "src"))
            write(joinpath(pkg, "Project.toml"), "name = \"DistSSHKit\"\n")
            job = joinpath(d, "MyJob")
            mkpath(job)
            write(joinpath(job, "Project.toml"), "name = \"MyJob\"\n")
            empty = joinpath(d, "scratch")
            mkpath(empty)
            src = joinpath(pkg, "src")
            @test DistSSHKit.kit_project_root(src) == pkg
            @test DistSSHKit._cli_job_root(pkg, job) == job
            @test DistSSHKit._cli_job_root(pkg, empty) == empty
            cd(job) do
                @test DistSSHKit.cli_project_root(src) == realpath(job)
            end
        end
        end
    end

    @testset "TeeIO drops \\r from secondary" begin
        let primary = IOBuffer(), secondary = IOBuffer()
            tee = DistSSHKit.TeeIO(primary, secondary)
            write(tee, Vector{UInt8}(codeunits("line1\r")))
            write(tee, Vector{UInt8}(codeunits("line2\n")))
            flush(tee)
            @test String(take!(primary)) == "line1\rline2\n"
            @test String(take!(secondary)) == "line2\n"
        end
    end

    @testset "records" begin
        @test DistSSHKit.subcommand_args_record("drive", ["l:2", "script.jl"]) ==
            "drive l:2 script.jl"
        @test "Julia binary" in first.(DistSSHKit.julia_env_record())
    end

    @testset "help chrome" begin
        buf = IOBuffer()
        DistSSHKit.print_cli_error("boom"; io=buf)
        @test occursin("Error:", String(take!(buf)))
        @test DistSSHKit._help_section_line("Usage:")
        @test !DistSSHKit._help_section_line("  indented:")
        @test !DistSSHKit._help_section_line("# comment:")
        txt = sprint(io -> DistSSHKit.print_help_document(
            "DistSSHKit test",
            "Usage:\n  cmd --help\n";
            io=io,
        ))
        @test occursin("DistSSHKit test", txt)
        @test occursin("cmd --help", txt)
    end

    @testset "verbosity gates" begin
        @testset "writeln_both: verbose terminal, quiet log-only" begin
            _with_tempdir() do tmp
                with_kit_verbosity(:quiet) do
                    out, _ = _capture_stdio() do _, _
                        DistSSHKit.init_log_file(tmp; prefix="gate_quiet")
                        DistSSHKit.writeln_both("quiet-secret")
                    end
                    DistSSHKit.close_log_file()
                    @test !occursin("quiet-secret", out)
                end
                with_kit_verbosity(:verbose) do
                    out, _ = _capture_stdio() do _, _
                        DistSSHKit.init_log_file(tmp; prefix="gate_verbose")
                        DistSSHKit.writeln_both("verbose-shown")
                    end
                    DistSSHKit.close_log_file()
                    @test occursin("verbose-shown", out)
                    @test occursin("Log file:", out)
                end
            end
        end

        @testset "quiet keeps kit log" begin
            _with_tempdir() do tmp
                with_kit_verbosity(:quiet) do
                    out, log_path = _capture_stdio() do _, _
                        path = DistSSHKit.init_log_file(tmp; prefix="quiet_test")
                        DistSSHKit.writeln_both("hello-quiet")
                        DistSSHKit.println_fatal("fatal-line")
                        return path
                    end
                    DistSSHKit.close_log_file()
                    body = read(log_path, String)
                    @test occursin("hello-quiet", body)
                    @test occursin("Log file:", body)
                    @test occursin("fatal-line", body)
                    @test occursin("fatal-line", out)
                    @test !occursin("hello-quiet", out)
                end
            end
        end

        @testset "progress keeps kit log, suppresses detail" begin
            _with_tempdir() do tmp
                with_kit_verbosity(:progress) do
                    @test DistSSHKit.kit_output_progress()
                    @test !DistSSHKit.kit_output_detail()
                    @test !DistSSHKit.kit_output_quiet()

                    log_path = DistSSHKit.init_log_file(tmp; prefix="progress_test")
                    redirect_stdout(devnull) do
                        DistSSHKit.writeln_both("hello-progress")
                    end
                    DistSSHKit.close_log_file()
                    @test occursin("hello-progress", read(log_path, String))
                end
            end
        end

        @testset "thin progress bar" begin
            empty = DistSSHKit._progress_bar_string(0, 1; tick=0)
            @test length(empty) == DistSSHKit.PROGRESS_BAR_WIDTH
            @test startswith(empty, string(DistSSHKit.PROGRESS_HEAD_CHAR))
            @test count(==(DistSSHKit.PROGRESS_HEAD_CHAR), empty) == 1

            full = DistSSHKit._progress_bar_string(1, 1)
            @test full == string(DistSSHKit.PROGRESS_FILL_CHAR)^DistSSHKit.PROGRESS_BAR_WIDTH
            @test !occursin(string(DistSSHKit.PROGRESS_HEAD_CHAR), full)

            half = DistSSHKit._progress_bar_string(3, 6; tick=0)
            @test length(half) == DistSSHKit.PROGRESS_BAR_WIDTH
            @test occursin(string(DistSSHKit.PROGRESS_FILL_CHAR), half)
            @test occursin(string(DistSSHKit.PROGRESS_HEAD_CHAR), half)
            @test collect(half)[DistSSHKit._progress_head_index(3, 6, 0)] ==
                DistSSHKit.PROGRESS_HEAD_CHAR

            let st = DistSSHKit.KitProgressState("drive", 6, 3, "workers")
                line = DistSSHKit._progress_line(st)
                @test startswith(line, "  ")
                @test occursin("workers", line)
                @test occursin("4/6", line)  # in-progress is done+1
                @test occursin(half, line)
                done_line = DistSSHKit._progress_line(st; finished=true, ok=true)
                @test occursin("drive", done_line)
                @test !occursin(half, done_line)
            end

            with_kit_verbosity(:verbose) do
                @test DistSSHKit._progress_can_draw() == false
            end
            with_kit_verbosity(:quiet) do
                @test DistSSHKit._progress_can_draw() == false
            end
            with_kit_verbosity(:progress) do
                withenv("NO_COLOR" => "1") do
                    @test DistSSHKit._progress_can_draw() == false
                end
            end

            _with_tempdir() do tmp
                with_kit_verbosity(:progress) do
                    log_path = DistSSHKit.init_log_file(tmp; prefix="progress_bar")
                    redirect_stdout(devnull) do
                        DistSSHKit.kit_progress_begin!("drive"; steps=2, kind=:drive)
                        DistSSHKit.kit_progress_step!("sync")
                        DistSSHKit.kit_progress_step!("run")
                        DistSSHKit.kit_progress_done!(; ok=true, footer="out/batch")
                    end
                    DistSSHKit.close_log_file()
                    body = read(log_path, String)
                    @test occursin("progress: begin kind=drive label=drive total=2", body)
                    @test occursin("progress: step kind=drive label=sync done=0 total=2 cur=1", body)
                    @test occursin("progress: step kind=drive label=run done=1 total=2 cur=2", body)
                    @test occursin("progress: done kind=drive ok=true done=2 total=2", body)
                    @test occursin("out/batch", body)
                    @test !occursin("→", body)
                end
            end

            _with_tempdir() do tmp
                with_kit_verbosity(:progress) do
                    log_path = DistSSHKit.init_log_file(tmp; prefix="progress_items")
                    redirect_stdout(devnull) do
                        DistSSHKit.kit_progress_begin!(
                            "go";
                            steps=2,
                            items=["local-1", "local-2"],
                            kind=:go,
                        )
                        DistSSHKit.kit_progress_item!("local-1"; status=:ok)
                        DistSSHKit.kit_progress_item!("local-2"; status=:ok)
                        DistSSHKit.kit_progress_done!(; ok=true, footer="out/batch")
                    end
                    DistSSHKit.close_log_file()
                    body = read(log_path, String)
                    @test occursin("progress: begin kind=go label=go total=2", body)
                    @test occursin(
                        "progress: item kind=go label=local-1 status=ok done=1 total=2",
                        body,
                    )
                    @test occursin(
                        "progress: item kind=go label=local-2 status=ok done=2 total=2",
                        body,
                    )
                    st = DistSSHKit.KitProgressState("go", 2, 0, "go")
                    push!(st.items, DistSSHKit.KitProgressItem("local-1", :running, 0))
                    push!(st.items, DistSSHKit.KitProgressItem("local-2", :running, 0))
                    @test DistSSHKit._progress_current(st) == 0
                    st.done = 1
                    @test DistSSHKit._progress_current(st) == 1
                end
            end

            @testset "job_id on progress: lines" begin
                _with_tempdir() do tmp
                    with_kit_verbosity(:progress) do
                        log_path = DistSSHKit.init_log_file(tmp; prefix="progress_job")
                        redirect_stdout(devnull) do
                            withenv("DISTSSHKIT_JOB_ID" => nothing) do
                                DistSSHKit.kit_progress_begin!(
                                    "drive"; steps=1, kind=:drive, job_id="q-42",
                                )
                                DistSSHKit.kit_progress_done!(; ok=true)
                            end
                        end
                        DistSSHKit.close_log_file()
                        body = read(log_path, String)
                        @test occursin(
                            "progress: begin kind=drive job=q-42 label=drive total=1",
                            body,
                        )
                        @test occursin(
                            "progress: done kind=drive job=q-42 ok=true done=1 total=1",
                            body,
                        )
                    end
                end

                # ENV fallback when `job_id` keyword is omitted.
                _with_tempdir() do tmp
                    with_kit_verbosity(:progress) do
                        log_path = DistSSHKit.init_log_file(tmp; prefix="progress_job_env")
                        redirect_stdout(devnull) do
                            withenv("DISTSSHKIT_JOB_ID" => "env-7") do
                                DistSSHKit.kit_progress_begin!("go"; steps=1, kind=:go)
                                DistSSHKit.kit_progress_done!(; ok=true)
                            end
                        end
                        DistSSHKit.close_log_file()
                        body = read(log_path, String)
                        @test occursin("progress: begin kind=go job=env-7", body)
                    end
                end

                # No job_id → format unchanged (no "job=" anywhere).
                _with_tempdir() do tmp
                    with_kit_verbosity(:progress) do
                        log_path = DistSSHKit.init_log_file(tmp; prefix="progress_no_job")
                        redirect_stdout(devnull) do
                            withenv("DISTSSHKIT_JOB_ID" => nothing) do
                                DistSSHKit.kit_progress_begin!("go"; steps=1, kind=:go)
                                DistSSHKit.kit_progress_done!(; ok=true)
                            end
                        end
                        DistSSHKit.close_log_file()
                        body = read(log_path, String)
                        @test !occursin("job=", body)
                    end
                end
            end

            _with_tempdir() do tmp
                for v in (:quiet, :verbose)
                    with_kit_verbosity(v) do
                        log_path = redirect_stdout(devnull) do
                            p = DistSSHKit.init_log_file(tmp; prefix="progress_done_$v")
                            DistSSHKit.kit_progress_begin!("drive"; steps=2, kind=:drive)
                            DistSSHKit.kit_progress_step!("sync")
                            DistSSHKit.kit_progress_done!(; ok=false)
                            p
                        end
                        DistSSHKit.close_log_file()
                        body = read(log_path, String)
                        @test !occursin("progress: begin", body)
                        @test !occursin("progress: step", body)
                        @test occursin(
                            "progress: done kind=drive ok=false done=2 total=2",
                            body,
                        )
                    end
                end
            end
        end

        @testset "parse_progress_line / kit_progress_latest" begin
            @test DistSSHKit.parse_progress_line("not progress") === nothing
            rec = DistSSHKit.parse_progress_line(
                "progress: step kind=drive job=q-1 label=sync done=0 total=2 cur=1",
            )
            @test rec !== nothing
            @test rec.event === :step
            @test rec.kind === :drive
            @test rec.job == "q-1"
            @test rec.label == "sync"
            @test rec.done == 0
            @test rec.total == 2
            @test rec.cur == 1
            @test rec.status === nothing
            @test rec.ok === nothing
            done = DistSSHKit.parse_progress_line(
                "progress: done kind=go ok=true done=2 total=2",
            )
            @test done.event === :done
            @test done.ok === true
            @test done.job === nothing
            _with_tempdir() do tmp
                a = joinpath(tmp, "a.log")
                b = joinpath(tmp, "b.log")
                write(a, "noise\nprogress: begin kind=drive job=old label=drive total=1\n")
                write(b, "progress: done kind=drive job=new ok=true done=1 total=1\n")
                latest = DistSSHKit.kit_progress_latest(tmp)
                @test latest.event === :done
                @test latest.job == "new"
                @test DistSSHKit.kit_progress_latest(a).event === :begin
                @test DistSSHKit.kit_progress_latest(tmp; job_id="old").job == "old"
                @test DistSSHKit.kit_progress_latest(tmp; job_id="missing") === nothing
            end
        end

        @testset "kit_output_dir_lock!" begin
            _with_tempdir() do tmp
                lock_path = joinpath(tmp, ".kit.lock")

                release = DistSSHKit.kit_output_dir_lock!(tmp)
                @test isfile(lock_path)
                @test strip(read(lock_path, String)) == string(getpid())

                # Re-locking under the same pid (re-entrant within one run) does not throw.
                release2 = DistSSHKit.kit_output_dir_lock!(tmp)
                @test isfile(lock_path)

                release2()
                @test !isfile(lock_path)
                release() # already-removed lock: no-op, must not throw
            end

            _with_tempdir() do tmp
                lock_path = joinpath(tmp, ".kit.lock")
                # A stale lock (dead pid) is reclaimed, not fatal.
                write(lock_path, "999999999")
                release = DistSSHKit.kit_output_dir_lock!(tmp)
                @test strip(read(lock_path, String)) == string(getpid())
                release()
                @test !isfile(lock_path)
            end

            _with_tempdir() do tmp
                lock_path = joinpath(tmp, ".kit.lock")
                write(lock_path, "1") # pid 1 (init/launchd) is always alive
                @test_throws ArgumentError DistSSHKit.kit_output_dir_lock!(tmp)
                @test strip(read(lock_path, String)) == "1" # left untouched on failure
            end
        end

        @testset "kit_spin! skips animation off verbose TTY" begin
            with_kit_verbosity(:quiet) do
                @test DistSSHKit._spinner_can_draw() == false
                @test DistSSHKit.kit_spin!("x: ") do
                    sleep(0.05)
                    42
                end == 42
            end
            with_kit_verbosity(:progress) do
                @test DistSSHKit._spinner_can_draw() == false
                @test DistSSHKit.kit_spin!("x: ") do
                    sleep(0.05)
                    42
                end == 42
            end
            with_kit_verbosity(:verbose) do
                withenv("NO_COLOR" => "1") do
                    @test DistSSHKit._spinner_can_draw() == false
                    @test DistSSHKit.kit_spin!("x: ") do
                        sleep(0.05)
                        42
                    end == 42
                end
            end
        end
    end
end
