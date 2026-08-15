using Test

# Oracle: demo listing, script lookup, missing-script diagnostics. Running the
# recipes is integration/demos/.

@testset "bundled demos" begin
    demos = DistSSHKit.list_demos()
    @test isdir(DistSSHKit.demos_dir())
    @test "with_kit/square_file" in demos
    @test "without_kit/pi_file" in demos
    @test "without_kit/pipeline_pi" in demos
    @test DistSSHKit.demo_script("square_file") !== nothing
    @test DistSSHKit.demo_script("no_such_demo") === nothing

    mktempdir() do tmp
        missing_kit = joinpath(tmp, "demos", "with_kit", "square_file.jl")
        diag = DistSSHKit.diagnose_missing_script(missing_kit, tmp)
        @test diag !== nothing
        @test diag.kind === :install_bundled
        @test occursin("demo install", DistSSHKit.explain_missing_script_hint(diag; surface=:cli))
        @test occursin(
            "DistSSHKit.install_demos()",
            DistSSHKit.explain_missing_script_hint(diag; surface=:api),
        )

        @test occursin(
            "demo install",
            something(DistSSHKit.missing_script_demo_hint(missing_kit, tmp; surface=:cli), ""),
        )
        @test occursin(
            "./demos/ is missing",
            something(DistSSHKit.missing_script_demo_hint(
                joinpath(tmp, "demos", "with_kit", "rho_sweep.jl"),
                tmp,
            ), ""),
        )
        @test DistSSHKit.missing_script_demo_hint(joinpath(tmp, "jobs", "x.jl"), tmp) === nothing

        api_msg = DistSSHKit.explain_script_not_found(
            joinpath(tmp, "demos", "with_kit", "rho_sweep.jl"),
            tmp;
            surface=:api,
            headline="script not found: x",
        )
        @test startswith(api_msg, "script not found: x")
        @test occursin("DistSSHKit.install_demos()", api_msg)

        @test DistSSHKit.join_explained_message("head", nothing) == "head"
        @test DistSSHKit.join_explained_message("head", "Hint: x") == "head\nHint: x"
    end

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

    let err = try
            DistSSHKit.install_demos(_kit_root(); surface=:api)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("install_demos(dest=", sprint(showerror, err))
        @test occursin("list_demos()", sprint(showerror, err))
    end
    let err = try
            DistSSHKit.install_demos(_kit_root(); surface=:cli)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("demo install --dest", sprint(showerror, err))
        @test occursin("demo list", sprint(showerror, err))
    end

    # CLI wiring smoke (install path covered by install_demos above).
    DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=true, yes=true))
    @test DistSSHKit.main(["demo", "--help"]) == 0
    @test redirect_stderr(devnull) do
        DistSSHKit.main(["demo", "bogus"])
    end == 1
    DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession())
end
