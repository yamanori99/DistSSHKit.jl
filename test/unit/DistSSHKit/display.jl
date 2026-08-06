using Test

@testset "display" begin
    @testset "paths" begin
        mktempdir() do tmp
            rel = joinpath(tmp, "nested")
            mkpath(rel)
            @test DistSSHKit.canonical_local_path(rel) == abspath(rel)
            @test DistSSHKit.canonical_local_path(joinpath("~", ".ssh")) ==
                abspath(expanduser(joinpath("~", ".ssh")))
        end

        let home = expanduser("~")
            @test DistSSHKit.short_path(joinpath(home, "foo", "bar")) == joinpath("~", "foo", "bar")
        end

        mktempdir() do tmp
            d = abspath(string(tmp))
            nested = joinpath(d, "a", "b.txt")
            mkpath(dirname(nested))
            write(nested, "")
            @test DistSSHKit.display_path(nested, d) == joinpath("a", "b.txt")
        end
    end

    @testset "project layout" begin
        # Standalone kit vs host-app embedding (the two layouts that matter).
        mktempdir() do tmp
            d = abspath(string(tmp))
            write(joinpath(d, "Project.toml"), "name = \"DistSSHKit\"\n")
            src = joinpath(d, "src")
            mkpath(src)
            @test DistSSHKit.kit_project_root(src) == d
            @test DistSSHKit.resolve_pkg_project_dir(d) == d
        end
        mktempdir() do tmp
            d = abspath(string(tmp))
            app = joinpath(d, "MyApp")
            kit = joinpath(app, "DistSSHKit")
            scripts = joinpath(app, "scripts", "jobs")
            mkpath(scripts)
            mkpath(joinpath(kit, "src"))
            write(joinpath(app, "Project.toml"), "name = \"MyApp\"\n")
            write(joinpath(kit, "Project.toml"), "name = \"DistSSHKit\"\n")
            @test DistSSHKit.kit_project_root(joinpath(kit, "src")) == app
            @test DistSSHKit.resolve_pkg_project_dir(scripts) == app
        end
        mktempdir() do tmp
            d = abspath(string(tmp))
            @test DistSSHKit.project_package_name(d) === nothing
            write(joinpath(d, "Project.toml"), "name = \"FooBar\"\n")
            @test DistSSHKit.project_package_name(d) == "FooBar"
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

    @testset "verbosity gates" begin
        # do-block form: `with_kit_verbosity(:quiet) do ... end`
        function with_kit_verbosity(f, v::Symbol)
            prev = DistSSHKit.kit_verbosity()
            try
                DistSSHKit.set_kit_verbosity!(v)
                return f()
            finally
                DistSSHKit.close_log_file()
                DistSSHKit.kit_progress_done!()  # no-op when idle
                DistSSHKit.set_kit_verbosity!(prev)
            end
        end

        @testset "quiet keeps kit log" begin
            mktempdir() do tmp
                with_kit_verbosity(:quiet) do
                    log_path = DistSSHKit.init_log_file(tmp; prefix="quiet_test")
                    DistSSHKit.writeln_both("hello-quiet")
                    DistSSHKit.println_fatal("fatal-line")
                    DistSSHKit.close_log_file()
                    body = read(log_path, String)
                    @test occursin("hello-quiet", body)
                    @test occursin("Log file:", body)
                    @test occursin("fatal-line", body)
                end
            end
        end

        @testset "progress keeps kit log, suppresses detail" begin
            mktempdir() do tmp
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
            half = DistSSHKit._progress_bar_string(3, 6)
            @test length(half) == DistSSHKit.PROGRESS_BAR_WIDTH
            @test occursin("━", half)
            @test occursin("─", half)
            @test half ==
                string(DistSSHKit.PROGRESS_FILL_CHAR)^8 *
                string(DistSSHKit.PROGRESS_EMPTY_CHAR)^8

            st = DistSSHKit.KitProgressState("drive", 6, 3, "workers")
            line = DistSSHKit._progress_line(st)
            @test startswith(line, "  ")
            @test occursin("workers · 3/6", line)
            @test occursin(half, line)

            @test DistSSHKit._progress_can_draw() == false  # not :progress yet
            with_kit_verbosity(:progress) do
                withenv("NO_COLOR" => "1") do
                    @test DistSSHKit._progress_can_draw() == false
                end
            end

            mktempdir() do tmp
                with_kit_verbosity(:progress) do
                    log_path = DistSSHKit.init_log_file(tmp; prefix="progress_bar")
                    redirect_stdout(devnull) do
                        DistSSHKit.kit_progress_begin!("drive"; steps=2)
                        DistSSHKit.kit_progress_step!("sync")
                        DistSSHKit.kit_progress_done!(; ok=true)
                    end
                    DistSSHKit.close_log_file()
                    body = read(log_path, String)
                    @test occursin("progress: drive (0/2)", body)
                    @test occursin("progress: sync (1/2)", body)
                    @test occursin("progress: sync (2/2)", body)
                end
            end
        end
    end
end
