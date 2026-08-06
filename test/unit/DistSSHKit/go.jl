using Test
using Dates

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
        @test_throws ArgumentError match(r"did you mean local", DistSSHKit._go_plan_slots(["lacal:0"]))
        @test occursin("root@", DistSSHKit._go_host_ssh_hint("192.0.2.11"))
        @test isempty(DistSSHKit._go_host_ssh_hint("root@192.0.2.11"))
        @test isdefined(DistSSHKit, :probe_remote_project_deps)
    end

    @testset "_go_batch_output_dir" begin
        mktempdir() do proj
            script = joinpath(proj, "demos", "demo.jl")
            mkpath(dirname(script))
            touch(script)
            t = DateTime(2026, 8, 3, 13, 44, 28)
            batch = DistSSHKit._go_batch_output_dir(proj, script; now=t)
            @test batch == joinpath(proj, ".distsshkit", "go", "demo_20260803T134428Z")
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
    end
end
