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
    lines = split(err, '\n')
    expected = only(filter(startswith("Expected:"), lines))
    queue = only(filter(startswith("Queue:"), lines))
    for c in run_cmds
        @test occursin(Regex("\\b\\Q$c\\E\\b"), expected)
    end
    for c in queue_cmds
        word = Regex("\\b\\Q$c\\E\\b")
        if c == "service"
            @test !occursin(word, expected)
            @test !occursin(word, queue)
        else
            @test occursin(word, queue)
        end
    end
    # Command column, not a later mention in prose (`up` inside `juliaup`).
    for c in (run_cmds..., queue_cmds...)
        column = Regex("^  (qhost )?\\Q$c\\E\\s{2,}", "m")
        if c == "service"
            @test !occursin(column, help)
        else
            @test occursin(column, help)
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
