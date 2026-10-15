# Command lists stay aligned with root help and the unknown-subcommand text.
# `service` is a route whose help says it is gone. Root help does not list it
# (NEWS 0.10.0).

@testset "command lists" begin
    run_cmds = DistSSHKit._RUN_COMMANDS
    queue_cmds = DistSSHKit._QUEUE_ONLY
    @test isdisjoint(run_cmds, queue_cmds)
    help = sprint(io -> DistSSHKit.print_kit_root_usage(io))
    code, _, err = _main_capture(["bogus"])
    @test code == 1
    for c in (run_cmds..., queue_cmds...)
        word = Regex("\\b\\Q$c\\E\\b")
        if c == "service"
            @test !occursin(word, help)
            @test !occursin(word, err)
        else
            @test occursin(word, help)
            @test occursin(word, err)
        end
    end
    for c in (run_cmds..., queue_cmds...)
        code, out, err = _main_capture([c, "--help"])
        text = out * err
        @test code == 0
        @test !occursin("julia -m DistSSHQueue", text)
        @test !occursin("julia -m DistSSHRun", text)
        c == "service" && @test occursin("gone", text)
    end
    for t in DistSSHKit._QUEUE_HELP_TOPICS
        code, _, _ = _main_capture(["--help", t])
        @test code == 0
    end
end
