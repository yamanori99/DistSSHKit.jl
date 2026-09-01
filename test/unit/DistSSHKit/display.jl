using Test

@testset "display" begin
    @testset "progress accent theme" begin
        withenv("DISTSSHKIT_PROGRESS_BG" => "light", "COLORFGBG" => nothing) do
            @test DistSSHKit._term_light_background()
            rgb, idx = DistSSHKit._progress_accent_pair()
            @test rgb == (3, 105, 161)
            @test idx == 31
        end
        withenv("DISTSSHKIT_PROGRESS_BG" => "dark") do
            @test !DistSSHKit._term_light_background()
            rgb, idx = DistSSHKit._progress_accent_pair()
            @test rgb == (56, 189, 248)
            @test idx == 81
        end
        withenv("DISTSSHKIT_PROGRESS_BG" => nothing, "COLORFGBG" => "0;15") do
            @test DistSSHKit._term_light_background()
        end
        withenv("DISTSSHKIT_PROGRESS_BG" => nothing, "COLORFGBG" => "15;0") do
            @test !DistSSHKit._term_light_background()
        end
    end

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

        @testset "progress bar glyphs" begin
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
            rec isa NamedTuple || return
            @test rec.event === :step
            @test rec.kind === :drive
            @test rec.job == "q-1"
            @test rec.label == "sync"
            @test rec.done == 0
            @test rec.total == 2
            @test rec.cur == 1
            @test rec.status === nothing
            @test rec.ok === nothing
            @test rec.t === nothing
            timed = DistSSHKit.parse_progress_line(
                "progress: done kind=drive ok=true done=1 total=1 t=1710000000.5",
            )
            timed isa NamedTuple || return
            @test timed.t == 1710000000.5
            _with_tempdir() do tmp
                p = joinpath(tmp, "kit.progress")
                write(
                    p,
                    "progress: begin kind=drive label=drive total=2 t=1.0\n" *
                    "progress: step kind=drive label=workers done=0 total=2 cur=1 t=2.5\n" *
                    "progress: done kind=drive ok=true done=2 total=2 t=3.0\n",
                )
                rows = DistSSHKit.kit_progress_phases(tmp)
                @test length(rows) == 2
                @test rows[1].label == "start"
                @test rows[1].seconds == 1.5
                @test rows[2].label == "workers"
                @test rows[2].seconds == 0.5
                open(p, "a") do io
                    write(
                        io,
                        "progress: begin kind=drive label=drive total=2 t=100.0\n" *
                        "progress: step kind=drive label=workers done=0 total=2 cur=1 t=101.0\n" *
                        "progress: done kind=drive ok=true done=2 total=2 t=104.0\n",
                    )
                end
                rows2 = DistSSHKit.kit_progress_phases(tmp)
                @test length(rows2) == 2
                @test rows2[2].seconds == 3.0
                mktemp() do out_path, out_io
                    code = redirect_stdout(out_io) do
                        DistSSHKit.progress([tmp])
                    end
                    flush(out_io)
                    @test code == 0
                    out = read(out_path, String)
                    @test occursin("Time", out)
                    @test occursin("3.00s", out)
                    @test occursin("workers", out)
                    @test occursin("%", out)
                    @test occursin("█", out)
                    @test !occursin("→", out)
                    @test !occursin("latest", out)
                end
                mktemp() do out_path, out_io
                    DistSSHKit._reset_job_stdout_capture!()
                    DistSSHKit._append_job_stdout_capture!(codeunits("param^2: [1, 4]\n"))
                    with_kit_verbosity(:progress) do
                        redirect_stdout(out_io) do
                            DistSSHKit._maybe_print_kit_progress_phases(tmp)
                        end
                    end
                    flush(out_io)
                    out = read(out_path, String)
                    @test occursin("param^2: [1, 4]", out)
                    @test occursin("workers", out)
                    @test occursin("progress  ", out)
                    @test findfirst("param^2", out) < findfirst("Time", out)
                end
                mktemp() do out_path, out_io
                    with_kit_verbosity(:progress) do
                        redirect_stdout(out_io) do
                            DistSSHKit._maybe_print_kit_progress_phases(tmp)
                        end
                    end
                    flush(out_io)
                    @test occursin("workers", read(out_path, String))
                    @test occursin("progress  ", read(out_path, String))
                end
                write(
                    p,
                    "progress: begin kind=go label=go total=2 t=1.0\n" *
                    "progress: step kind=go label=sync done=0 total=2 cur=0 t=1.2\n" *
                    "progress: item kind=go label=local-1 status=running done=0 total=2 t=2.0\n" *
                    "progress: item kind=go label=local-1/run status=running done=0 total=2 t=2.0\n" *
                    "progress: item kind=go label=local-2 status=running done=0 total=2 t=2.1\n" *
                    "progress: item kind=go label=local-2/run status=running done=0 total=2 t=2.1\n" *
                    "progress: item kind=go label=local-1/run status=ok done=0 total=2 t=4.5\n" *
                    "progress: item kind=go label=local-1/collect status=running done=0 total=2 t=4.5\n" *
                    "progress: item kind=go label=local-1/collect status=ok done=0 total=2 t=5.0\n" *
                    "progress: item kind=go label=local-1 status=ok done=1 total=2 t=5.0\n" *
                    "progress: item kind=go label=local-2/run status=ok done=1 total=2 t=8.0\n" *
                    "progress: item kind=go label=local-2 status=ok done=2 total=2 t=8.0\n" *
                    "progress: done kind=go ok=true done=2 total=2 t=8.1\n",
                )
                grows = DistSSHKit.kit_progress_phases(tmp)
                labs = [r.label for r in grows]
                @test "sync" in labs
                @test "local-1" in labs
                @test "local-1/run" in labs
                @test "local-1/collect" in labs
                @test "local-2" in labs
                @test grows[findfirst(==("local-1"), labs)].seconds == 3.0
                @test grows[findfirst(==("local-1/run"), labs)].seconds == 2.5
                @test grows[findfirst(==("local-1/collect"), labs)].seconds == 0.5
                @test grows[findfirst(==("local-2"), labs)].seconds == 5.9
                grouped = DistSSHKit._format_kit_progress_phases(grows; wall=7.1)
                @test occursin("local-1", grouped)
                @test occursin("  run", grouped)
                @test occursin("  collect", grouped)
                @test occursin("script", grouped)
                @test occursin("pull results", grouped)
                @test occursin("slot", grouped)
                write(
                    p,
                    "progress: begin kind=go label=go total=1 t=1.0\n" *
                    "progress: step kind=go label=ready done=0 total=1 cur=0 t=1.1\n" *
                    "progress: step kind=go label=sync done=0 total=1 cur=0 t=1.2\n" *
                    "progress: step kind=go label=run done=0 total=1 cur=0 t=1.3\n" *
                    "progress: item kind=go label=parent/run status=running done=0 total=1 t=1.4\n" *
                    "progress: item kind=go label=parent/run status=ok done=0 total=1 t=5.0\n" *
                    "progress: item kind=go label=parent status=ok done=1 total=1 t=5.0\n" *
                    "progress: step kind=go label=collect done=1 total=1 cur=1 t=5.1\n" *
                    "progress: done kind=go ok=true done=1 total=1 t=5.2\n",
                )
                prows = DistSSHKit.kit_progress_phases(tmp)
                plabs = [r.label for r in prows]
                @test "ready" in plabs
                @test "sync" in plabs
                @test "run" in plabs
                @test "collect" in plabs
                @test prows[findfirst(==("run"), plabs)].seconds == 3.8
                @test prows[findfirst(==("collect"), plabs)].seconds ≈ 0.1
                ptext = DistSSHKit._format_kit_progress_phases(prows)
                @test occursin("script", ptext)
                @test !occursin("driver script", ptext)
                write(
                    p,
                    "progress: begin kind=drive label=drive total=7 t=1.0\n" *
                    "progress: step kind=drive label=workers done=3 total=7 cur=4 t=8.0\n" *
                    "progress: item kind=drive label=parent/workers status=running done=3 total=7 t=8.0\n" *
                    "progress: item kind=drive label=parent/workers status=ok done=3 total=7 t=10.5\n" *
                    "progress: item kind=drive label=parent/init status=running done=5 total=7 t=15.5\n" *
                    "progress: item kind=drive label=parent/init status=ok done=5 total=7 t=16.0\n" *
                    "progress: done kind=drive ok=true done=7 total=7 t=16.0\n",
                )
                drows = DistSSHKit.kit_progress_phases(tmp)
                dtext = DistSSHKit._format_kit_progress_phases(drows)
                @test occursin("parent", dtext)
                @test occursin("  workers", dtext)
                @test occursin("  init", dtext)
                @test occursin("activate project", dtext)
                write(
                    p,
                    "progress: begin kind=setup label=setup total=1 t=1.0\n" *
                    "progress: step kind=setup label=rsync done=0 total=1 cur=1 t=1.0\n" *
                    "progress: item kind=setup label=rsync/h1 status=running done=0 total=1 t=1.1\n" *
                    "progress: item kind=setup label=rsync/h2 status=running done=0 total=1 t=1.1\n" *
                    "progress: item kind=setup label=rsync/h1 status=ok done=0 total=1 t=3.1\n" *
                    "progress: item kind=setup label=rsync/h2 status=ok done=0 total=1 t=4.1\n" *
                    "progress: done kind=setup ok=true done=1 total=1 t=4.2\n",
                )
                srows = DistSSHKit.kit_progress_phases(tmp)
                stext = DistSSHKit._format_kit_progress_phases(srows)
                @test occursin("rsync", stext)
                @test occursin("  h1", stext)
                @test occursin("  h2", stext)
                @test occursin("host", stext)
            end
            done = DistSSHKit.parse_progress_line(
                "progress: done kind=go ok=true done=2 total=2",
            )
            done isa NamedTuple || return
            @test done.event === :done
            @test done.ok === true
            @test done.job === nothing
            _with_tempdir() do tmp
                a = joinpath(tmp, "a.log")
                b = joinpath(tmp, "b.log")
                write(a, "noise\nprogress: begin kind=drive job=old label=drive total=1\n")
                write(b, "progress: done kind=drive job=new ok=true done=1 total=1\n")
                latest = DistSSHKit.kit_progress_latest(tmp)
                latest isa NamedTuple || return
                @test latest.event === :done
                @test latest.job == "new"
                oldrec = DistSSHKit.kit_progress_latest(a)
                oldrec isa NamedTuple || return
                @test oldrec.event === :begin
                by_job = DistSSHKit.kit_progress_latest(tmp; job_id="old")
                by_job isa NamedTuple || return
                @test by_job.job == "old"
                @test DistSSHKit.kit_progress_latest(tmp; job_id="missing") === nothing
            end
            _with_tempdir() do tmp
                DistSSHKit._set_kit_progress_sidecar!(tmp)
                try
                    with_kit_verbosity(:quiet) do
                        DistSSHKit.kit_progress_begin!("drive"; steps=1, kind=:drive)
                        DistSSHKit.kit_progress_done!(; ok=true)
                    end
                    sidecar = joinpath(tmp, "kit.progress")
                    @test isfile(sidecar)
                    body = read(sidecar, String)
                    @test occursin("progress: begin kind=drive", body)
                    @test occursin("progress: done kind=drive ok=true", body)
                    got = DistSSHKit.kit_progress_latest(tmp)
                    got isa NamedTuple || return
                    @test got.event === :done
                    side = DistSSHKit.kit_progress_latest(sidecar)
                    side isa NamedTuple || return
                    @test side.event === :done
                finally
                    DistSSHKit._set_kit_progress_sidecar!(nothing)
                end
            end
            _with_tempdir() do tmp
                DistSSHKit._set_kit_progress_sidecar!(tmp)
                try
                    redirect_stdout(devnull) do
                        with_kit_verbosity(:progress) do
                            DistSSHKit.kit_progress_begin!("drive"; steps=1, kind=:drive)
                            DistSSHKit.kit_progress_done!(; ok=true)
                        end
                    end
                    body = read(joinpath(tmp, "kit.progress"), String)
                    @test occursin("progress: begin kind=drive", body)
                    @test occursin("progress: done kind=drive ok=true", body)
                finally
                    DistSSHKit._set_kit_progress_sidecar!(nothing)
                end
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
