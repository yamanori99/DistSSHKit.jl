using Test

@testset "(@main) dispatch" begin
    # `julia -m DistSSHKit` invokes this module's `main` (the `(@main)` entry point).
    # Redirect CLI help text so test output stays readable.
    function _main_quiet(args)
        withenv("DISTSSHKIT_CLI_SUBCOMMAND_DONE" => "") do
            redirect_stdout(devnull) do
                redirect_stderr(devnull) do
                    return DistSSHKit.main(args)
                end
            end
        end
    end
    @test _main_quiet(String[]) == 1
    # Unknown first token (typo / mistaken flag-as-subcommand) must fail, not exit 0.
    @test _main_quiet(["bogus"]) == 1
    @test _main_quiet(["rysnc", "host1"]) == 1
    @test _main_quiet(["drive", "--help"]) == 0
    @test _main_quiet(["go", "--help"]) == 0
    @test _main_quiet(["setup", "--help"]) == 0
    @test _main_quiet(["size", "--help"]) == 0
    @test _main_quiet(["-h"]) == 0
    @test _main_quiet(["--help"]) == 0
    @test _main_quiet(["drive", "-h"]) == 0
    @test _main_quiet(["--version"]) == 0
    @test _main_quiet(["drive", "--version"]) == 0
end
