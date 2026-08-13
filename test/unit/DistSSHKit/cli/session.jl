using Test

@testset "cli_session" begin
    clear_verbosity_env = (
        "DISTSSHKIT_QUIET" => nothing,
        "DISTSSHKIT_PROGRESS" => nothing,
        "DISTSSHKIT_VERBOSE" => nothing,
    )

    @testset "peel flags" begin
        withenv(clear_verbosity_env..., "DISTSSHKIT_YES" => nothing) do
            let (session, rest) = DistSSHKit.peel_kit_cli_flags(["--quiet", "--yes", "host1", "s.jl"])
                @test session.quiet
                @test session.verbosity === :quiet
                @test session.yes
                @test rest == ["host1", "s.jl"]
            end

            let (session, rest) = DistSSHKit.peel_kit_cli_flags(["--verbose", "host1"])
                @test session.verbosity === :verbose
                @test !session.quiet
                @test rest == ["host1"]
            end

            let (session, rest) = DistSSHKit.peel_kit_cli_flags(["host1", "s.jl"])
                @test session.verbosity === DistSSHKit.kit_cli_auto_verbosity()
                @test rest == ["host1", "s.jl"]
            end

            for flag in ("--version", "-v", "-V")
                let (session, rest) = DistSSHKit.peel_kit_cli_flags([flag])
                    @test session.show_version
                    @test rest == String[]
                end
            end
        end
    end

    @testset "quiet vs progress exclusivity" begin
        withenv(clear_verbosity_env...) do
            @test_throws ArgumentError DistSSHKit.peel_kit_cli_flags(["-q", "--progress"])
            @test_throws ArgumentError DistSSHKit.peel_kit_cli_flags(["--progress", "--quiet"])
            @test_throws ArgumentError DistSSHKit.peel_kit_cli_flags(["--progress", "--verbose"])
            @test_throws ArgumentError DistSSHKit.peel_kit_cli_flags(["--verbose", "-q"])
            @test_throws ArgumentError DistSSHKit.KitCliSession(quiet=true, verbosity=:progress)
        end
        withenv("DISTSSHKIT_QUIET" => "1", "DISTSSHKIT_PROGRESS" => "1") do
            @test_throws ArgumentError DistSSHKit.default_kit_cli_session()
        end
        withenv("DISTSSHKIT_VERBOSE" => "1", "DISTSSHKIT_PROGRESS" => "1", "DISTSSHKIT_QUIET" => nothing) do
            @test_throws ArgumentError DistSSHKit.default_kit_cli_session()
        end
    end

    @testset "ENV defaults" begin
        withenv("DISTSSHKIT_QUIET" => "1", "DISTSSHKIT_YES" => "true", "DISTSSHKIT_PROGRESS" => nothing, "DISTSSHKIT_VERBOSE" => nothing) do
            session = DistSSHKit.default_kit_cli_session()
            @test session.quiet
            @test session.verbosity === :quiet
            @test session.yes
        end
        withenv("DISTSSHKIT_QUIET" => nothing, "DISTSSHKIT_PROGRESS" => "1", "DISTSSHKIT_VERBOSE" => nothing, "DISTSSHKIT_YES" => nothing) do
            session = DistSSHKit.default_kit_cli_session()
            @test session.verbosity === :progress
            @test !session.quiet
        end
        withenv("DISTSSHKIT_QUIET" => nothing, "DISTSSHKIT_PROGRESS" => nothing, "DISTSSHKIT_VERBOSE" => "1", "DISTSSHKIT_YES" => nothing) do
            session = DistSSHKit.default_kit_cli_session()
            @test session.verbosity === :verbose
            @test !session.quiet
        end
        @test DistSSHKit.kit_cli_auto_verbosity(; live=true) === :progress
        @test DistSSHKit.kit_cli_auto_verbosity(; live=false) === :verbose
    end

    @testset "apply_kit_cli_session!" begin
        withenv(clear_verbosity_env..., "DISTSSHKIT_YES" => nothing) do
            prev = DistSSHKit.kit_verbosity()
            try
                DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(yes=true))
                @test DistSSHKit.kit_confirm("ignored")

                DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(verbosity=:progress))
                @test DistSSHKit.kit_verbosity() === :progress
                @test DistSSHKit.kit_output_progress()
                @test !DistSSHKit.kit_output_detail()
                @test !DistSSHKit.kit_output_quiet()

                DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(verbosity=:verbose))
                @test DistSSHKit.kit_verbosity() === :verbose
                @test DistSSHKit.kit_output_detail()
            finally
                DistSSHKit.set_kit_verbosity!(prev)
            end
        end
    end

    @testset "shared help constants" begin
        @test occursin("--progress", DistSSHKit.KIT_PROGRESS_FLAG_HELP)
        @test occursin("TTY default", DistSSHKit.KIT_PROGRESS_FLAG_HELP)
        @test occursin("--verbose", DistSSHKit.KIT_VERBOSE_FLAG_HELP)
        @test occursin("DISTSSHKIT_PROGRESS", DistSSHKit.KIT_PROGRESS_ENV_HELP)
        @test occursin("DISTSSHKIT_VERBOSE", DistSSHKit.KIT_VERBOSE_ENV_HELP)
        @test occursin("-q, --quiet", DistSSHKit.KIT_QUIET_FLAG_HELP)
    end

    @testset "hosts file" begin
        hosts_file = _sample_hosts_file()
        @test DistSSHKit.read_hosts_file_lines(hosts_file) == ["host-a", "host-b:4"]
        @test DistSSHKit.read_hosts_file(hosts_file) == ["host-a", "host-b"]
        @test DistSSHKit.split_host_workers_spec("host-b:4") == ("host-b", 4)

        # go keeps host:N from the file when planning slots.
        let lines = DistSSHKit.read_hosts_file_lines(hosts_file)
            slots = DistSSHKit._go_plan_slots(lines)
            @test length(slots) == 5  # host-a + host-b:4
            @test count(s -> s.host == "host-b", slots) == 4
        end
    end
end
