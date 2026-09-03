using Test
using Dates

# Oracle: slot plan, batch paths, julia resolve, missing-script surfaces, remote
# shell strings. Concurrent local `go!` is integration/go/overlap.jl.

@testset "go" begin
    @testset "_go_plan_slots" begin
        let s = DistSSHKit._go_plan_slots(String[])
            @test length(s) == 1
            @test s[1].kind === :parent
            @test s[1].label == "parent"
        end
        let s = DistSSHKit._go_plan_slots(["child:local:2"])
            @test length(s) == 2
            @test s[1].kind === :child && s[1].label == "local-1"
            @test s[2].kind === :child && s[2].label == "local-2"
        end
        let s = DistSSHKit._go_plan_slots(["child:user@lab", "child:user@lab2:2"])
            @test length(s) == 3
            @test s[1].kind === :child && s[1].label == "user@lab"
            @test s[2].label == "user@lab2-1"
            @test s[3].label == "user@lab2-2"
        end
        let s = DistSSHKit._go_plan_slots(["parent:0", "child:h1", "child:h2"])
            @test length(s) == 2
            @test all(x -> x.kind === :child, s)
        end
        @test_throws ArgumentError DistSSHKit._go_plan_slots(["parent:0"])
        @test_throws ArgumentError DistSSHKit._go_plan_slots(["child:local:0"])
        @test_throws ArgumentError DistSSHKit._go_plan_slots(["child:local:-1"])
        @test DistSSHKit._go_sanitize_label("user@lab") == "user@lab"
        @test DistSSHKit._go_sanitize_label("a/b c") == "a_b_c"
        @test DistSSHKit._go_sanitize_label("***") == "_"
        err = try
            DistSSHKit._go_plan_slots(["lacal:0"])
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("child:NAME", sprint(showerror, err))
        let s = DistSSHKit._go_plan_slots(["parent:2"])
            @test length(s) == 2
            @test s[1].label == "parent-1"
            @test s[2].label == "parent-2"
        end
        @test occursin("root@", DistSSHKit._go_host_ssh_hint("192.0.2.11"))
        @test isempty(DistSSHKit._go_host_ssh_hint("root@192.0.2.11"))
    end

    @testset "_go_script_relpath" begin
        _with_tempdir() do proj
            nested = joinpath(proj, "demos", "job.jl")
            mkpath(dirname(nested))
            touch(nested)
            @test DistSSHKit._go_script_relpath(proj, nested) == joinpath("demos", "job.jl")
            @test_throws ArgumentError DistSSHKit._go_script_relpath(proj, "/tmp/outside.jl")
        end
    end

    @testset "_go_batch_output_dir" begin
        _with_tempdir() do proj
            script = joinpath(proj, "demos", "demo.jl")
            mkpath(dirname(script))
            touch(script)
            t = DateTime(2026, 8, 3, 13, 44, 28)
            batch = DistSSHKit._go_batch_output_dir(proj, script; now=t)
            @test batch == joinpath(proj, "demos", ".distsshkit", "go", "demo_20260803T134428Z")
            nested = joinpath(proj, "demos", "without_kit", "job.jl")
            mkpath(dirname(nested))
            touch(nested)
            nested_batch = DistSSHKit._go_batch_output_dir(proj, nested; now=t)
            @test nested_batch == joinpath(proj, "demos", "without_kit", ".distsshkit", "go", "job_20260803T134428Z")
            outside = joinpath(tempdir(), "outside-job.jl")
            write(outside, "nothing\n")
            other = DistSSHKit._go_batch_output_dir(proj, outside; now=t)
            @test other == joinpath(proj, ".distsshkit", "go", "outside-job_20260803T134428Z")
        end
    end

    @testset "_go_slot_exitcode" begin
        _with_tempdir() do d
            ssh0 = 0
            missing = joinpath(d, "no-such")
            @test DistSSHKit._go_slot_exitcode(ssh0, missing; scp_failed=false) == 0
            @test DistSSHKit._go_slot_exitcode(ssh0, missing; scp_failed=true) == 1
            @test DistSSHKit._go_slot_exitcode(7, missing; scp_failed=false) == 7
            ec = joinpath(d, "go.exitcode")
            write(ec, "3\n")
            @test DistSSHKit._go_slot_exitcode(ssh0, ec; scp_failed=true) == 1
            @test DistSSHKit._go_slot_exitcode(ssh0, ec; scp_failed=false) == 3
            write(ec, "0\n")
            @test DistSSHKit._go_slot_exitcode(ssh0, ec; scp_failed=true) == 1
        end
    end

    @testset "output_dir + collect_spec::String errors" begin
        _with_tempdir() do proj
            script = joinpath(proj, "job.jl")
            write(script, "nothing\n")
            err = try
                DistSSHKit.go!(
                    script,
                    ["parent:1"];
                    project=proj,
                    output_dir=joinpath(proj, "a"),
                    collect_spec=joinpath(proj, "b"),
                    quiet=true,
                )
                nothing
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("not both", sprint(showerror, err))
        end
    end

    @testset "_go_resolve_julia" begin
        real = DistSSHKit._go_julia_exe()
        @test DistSSHKit._go_resolve_julia(nothing) == real
        @test DistSSHKit._go_resolve_julia("auto") == real
        @test DistSSHKit._go_resolve_julia(real) == real
        @test_throws ArgumentError DistSSHKit._go_resolve_julia("/no/such/julia-bin")
        @test_throws ArgumentError DistSSHKit._go_resolve_julia("auto"; host="no-such-host.invalid")
    end

    @testset "script not found surfaces" begin
        _with_tempdir() do tmp
            missing = joinpath(tmp, "demos", "with_kit", "rho_sweep.jl")
            err_api = try
                DistSSHKit.go!(missing, String[]; project=tmp)
                nothing
            catch e
                e
            end
            @test err_api isa ArgumentError
            @test occursin("DistSSHKit.install_demos(; family=", sprint(showerror, err_api))

            err_cli = try
                DistSSHKit.go!(missing, String[]; project=tmp, hint_surface=:cli)
                nothing
            catch e
                e
            end
            @test err_cli isa ArgumentError
            @test occursin("demo install", sprint(showerror, err_cli))
        end
    end

    @testset "_go_remote_slot_shell_inner" begin
        inner = DistSSHKit._go_remote_slot_shell_inner(
            "~/proj",
            "demos/output/go_sim/root@192.0.2.10-1",
            "demos/pi_file.jl",
            String[],
            "julia",
        )
        @test startswith(inner, "cd ")
        @test occursin("cd ~/proj && mkdir -p demos/output/go_sim/root@192.0.2.10-1", inner)
        @test occursin(">demos/output/go_sim/root@192.0.2.10-1/julia.stdout.log", inner)
        @test occursin("go.exitcode", inner)
        @test occursin("echo \$ec >", inner)

        spaced = DistSSHKit._go_remote_slot_shell_inner(
            "~/proj",
            "slot",
            "job.jl",
            String[],
            "/opt/Julia 1.12/bin/julia",
        )
        @test occursin(Base.shell_escape("/opt/Julia 1.12/bin/julia"), spaced)

        with_args = DistSSHKit._go_remote_slot_shell_inner(
            "~/proj",
            "slot",
            "job.jl",
            ["8", "a b"],
            "julia",
        )
        @test occursin("julia --project=. job.jl 8 " * Base.shell_escape("a b"), with_args)

        withenv("DISTSSHKIT_JOB_ID" => "repro-1") do
            tagged = DistSSHKit._go_remote_slot_shell_inner(
                "~/proj",
                "slot",
                "job.jl",
                String[],
                "julia",
            )
            @test occursin(" -L ", tagged)
            @test occursin("distsshkit-job:repro-1", tagged)
            @test occursin("printf '%s\\n' '#distsshkit-job:repro-1'", tagged)
            @test !occursin("--eval=", tagged)
            @test !occursin("include(popfirst!(ARGS))", tagged)
        end
    end

    @testset "job_id slot programfile + ARGS" begin
        _with_tempdir() do d
            write(joinpath(d, "Project.toml"), "[deps]\n")
            mark = joinpath(d, "RAN")
            argsf = joinpath(d, "ARGS")
            envf = joinpath(d, "ENVJOB")
            progf = joinpath(d, "PROGRAM")
            script = joinpath(d, "mark.jl")
            write(script, """
                write($(repr(mark)), "yes")
                write($(repr(argsf)), join(ARGS, '\\n'))
                write($(repr(envf)), get(ENV, "DISTSSHKIT_JOB_ID", ""))
                write($(repr(progf)), PROGRAM_FILE)
                """)
            slot = joinpath(d, "slot")
            withenv("DISTSSHKIT_JOB_ID" => "repro-1") do
                r = DistSSHKit._go_run_local_slot!(
                    d, script, ["a", "b c"], slot; quiet=true,
                )
                @test r.ok
            end
            @test isfile(mark)
            @test split(read(argsf, String), '\n'; keepempty=false) == ["a", "b c"]
            @test strip(read(envf, String)) == "repro-1"
            @test abspath(strip(read(progf, String))) == abspath(script)
            @test isfile(joinpath(slot, DistSSHKit.kit_job_pkill_pattern("repro-1")))
        end
    end

    @testset "report_go_errors" begin
        ok = DistSSHKit.GoResult(true, nothing, nothing, nothing, "job.jl", "/out")
        @test DistSSHKit.report_go_errors(ok)
        bad = DistSSHKit.GoResult(
            false,
            DistSSHKit.SyncResult(false, [DistSSHKit.HostResult("h1", false, "pull failed")], false),
            DistSSHKit.DriveResult(false, 2),
            DistSSHKit.CollectResult(false, 1),
            "job.jl",
            "/tmp/go-out";
            failed_step="run",
        )
        buf = IOBuffer()
        @test !DistSSHKit.report_go_errors(bad; io=buf)
        txt = String(take!(buf))
        @test occursin("go failed at step: run", txt)
        @test occursin("output: /tmp/go-out", txt)
        @test occursin("sync h1: pull failed", txt)
        @test occursin("run exit 2", txt)
        @test occursin("collect exit 1", txt)
        kr = DistSSHKit.kit_run_result(bad)
        @test kr.kind === :go
        @test kr.output_dir == "/tmp/go-out"
        @test kr.exit_code == 2
        @test !DistSSHKit.report_run_errors(bad; io=IOBuffer())
    end

    @testset "quiet suppresses Log file on stdout" begin
        _with_tempdir() do proj
            write(joinpath(proj, "Project.toml"), "name = \"GoQuietLog\"\n")
            script = joinpath(proj, "job.jl")
            write(script, "true\n")
            with_kit_verbosity(:verbose) do
                out, _ = _capture_stdio() do _, _
                    DistSSHKit.go!(
                        script, ["parent:1"];
                        project=proj, quiet=true, yes=true,
                    )
                end
                @test !occursin("Log file:", out)
            end
            r = redirect_stdout(devnull) do
                DistSSHKit.go!(
                    script, ["parent:1"];
                    project=proj, quiet=true, yes=true,
                    original_args=["parent:1", "job.jl"],
                )
            end
            @test r.ok
            logs = filter(n -> startswith(n, "go_") && endswith(n, ".log"), readdir(r.output_dir))
            @test length(logs) == 1
            body = read(joinpath(r.output_dir, only(logs)), String)
            @test occursin("Subcommand args: go", body)
            @test occursin("Julia binary:", body)
            @test occursin("DistSSHKit:", body)
            @test occursin("Project:", body)
            @test occursin("Slots: 1", body)
            prog = read(joinpath(r.output_dir, "kit.progress"), String)
            @test occursin("label=ready", prog)
            @test occursin("label=sync", prog)
            @test occursin("label=run", prog)
            @test occursin("label=collect", prog)
            run_mark = findfirst("step kind=go label=run", prog)
            collect_mark = findfirst("step kind=go label=collect", prog)
            @test run_mark !== nothing && collect_mark !== nothing
            @test first(run_mark) < first(collect_mark)
            run_span = findlast("label=parent/run", prog)
            @test run_span !== nothing
            @test first(run_span) < first(collect_mark)
        end
    end

    @testset "DISTSSHKIT_HOSTS_FILE not reapplied when workers set" begin
        _with_tempdir() do proj
            script = joinpath(proj, "job.jl")
            write(script, "true\n")
            hf = joinpath(proj, "hosts")
            write(hf, "child:no-such-host.invalid:1\n")
            withenv("DISTSSHKIT_HOSTS_FILE" => hf) do
                redirect_stdout(devnull) do
                    r = DistSSHKit.go!(
                        script, ["parent:1"];
                        project=proj, quiet=true, yes=true,
                    )
                    @test r.ok
                end
            end
        end
    end
end
