using Test
using Dates

# Oracle: slot plan, batch paths, julia resolve, missing-script surfaces, remote
# shell strings. Concurrent local `go!` is integration/go/overlap.jl.

@testset "go" begin
    @testset "_go_plan_slots" begin
        let s = DistSSHKit._go_plan_slots(String[])
            @test length(s) == 1
            @test s[1].kind === :local
            @test s[1].label == "local"
        end
        let s = DistSSHKit._go_plan_slots(["local:2"])
            @test length(s) == 2
            @test s[1].label == "local-1"
            @test s[2].label == "local-2"
        end
        let s = DistSSHKit._go_plan_slots(["user@lab", "user@lab2:2"])
            @test length(s) == 3
            @test s[1].kind === :remote && s[1].label == "user@lab"
            @test s[2].label == "user@lab2-1"
            @test s[3].label == "user@lab2-2"
        end
        let s = DistSSHKit._go_plan_slots(["local:0", "h1", "h2"])
            @test length(s) == 2
            @test all(x -> x.kind === :remote, s)
        end
        @test_throws ArgumentError DistSSHKit._go_plan_slots(["local:0"])
        @test_throws ArgumentError DistSSHKit._go_plan_slots(["local:-1"])
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
        @test occursin("did you mean local", sprint(showerror, err))
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
            @test batch == joinpath(proj, ".distsshkit", "go", "demo_20260803T134428Z")
        end
    end

    @testset "output_dir + collect_spec::String errors" begin
        _with_tempdir() do proj
            script = joinpath(proj, "job.jl")
            write(script, "nothing\n")
            err = try
                DistSSHKit.go!(
                    script,
                    ["local:1"];
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
    end
end
