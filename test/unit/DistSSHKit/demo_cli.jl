using Test

@testset "bundled demos" begin
    demos = DistSSHKit.list_demos()
    @test isdir(DistSSHKit.demos_dir())
    @test "with_kit/square_file" in demos
    @test "without_kit/pi_file" in demos
    @test "without_kit/pipeline_pi" in demos
    @test DistSSHKit.demo_script("square_file") !== nothing
    @test DistSSHKit.demo_script("no_such_demo") === nothing

    mktempdir() do tmp
        result = DistSSHKit.install_demos(tmp)
        @test length(result.installed) == length(DistSSHKit.list_demos())
        @test isempty(result.skipped)
        @test isfile(joinpath(tmp, "demos", "with_kit", "square_file.jl"))
        @test isfile(joinpath(tmp, "demos", "with_kit", "pipeline_square.jl"))
        @test isfile(joinpath(tmp, "demos", "without_kit", "pipeline_pi.jl"))
        @test isfile(joinpath(tmp, "demos", ".gitignore"))
        @test occursin("init_output_dir!", read(joinpath(tmp, "demos", "with_kit", "square_file.jl"), String))

        edited_path = joinpath(tmp, "demos", "with_kit", "square_file.jl")
        write(edited_path, "# edited by user\n")
        result2 = DistSSHKit.install_demos(tmp)
        @test isempty(result2.installed)
        # Existing demo scripts + demos/.gitignore are left untouched without --force.
        @test length(result2.skipped) == length(result.installed) + 1
        @test read(edited_path, String) == "# edited by user\n"

        result3 = DistSSHKit.install_demos(tmp; force=true)
        @test isempty(result3.skipped)
        @test occursin("init_output_dir!", read(edited_path, String))
    end

    @test_throws ArgumentError DistSSHKit.install_demos(_kit_root())

    # CLI wiring smoke (install path covered by install_demos above).
    DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=true, yes=true))
    @test DistSSHKit.main(["demo", "--help"]) == 0
    @test redirect_stderr(devnull) do
        DistSSHKit.main(["demo", "bogus"])
    end == 1
    DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession())
end
