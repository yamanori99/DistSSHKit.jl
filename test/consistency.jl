# Command lists stay aligned with root help and the unknown-subcommand text.
# `service` is a route. Root help does not list it (NEWS 0.10.0).
# Each forwarded page equals that owner's `main` (code, stdout, and stderr).

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
    for c in run_cmds, flag in ("-h", "--help")
        _test_same_page([c, flag], DistSSHRun.main)
    end
    for c in queue_cmds, flag in ("-h", "--help")
        _test_same_page([c, flag], DistSSHQueue.main)
        # The group word is Kit's. Spell the stripped owner argv here.
        _test_same_page(["qhost", c, flag], DistSSHQueue.main, [c, flag])
    end
    for t in DistSSHKit._QUEUE_HELP_TOPICS, flag in ("-h", "--help", "help")
        _test_same_page([flag, t], DistSSHQueue.main)
    end
end
