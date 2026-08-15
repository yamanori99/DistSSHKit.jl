using Test

@testset "(@main) dispatch" begin
    # `julia -m DistSSHKit` invokes this module's `main`.
    function _main_capture(args)
        mktemp() do out_path, out_io
            mktemp() do err_path, err_io
                code = withenv("DISTSSHKIT_CLI_SUBCOMMAND_DONE" => "") do
                    redirect_stdout(out_io) do
                        redirect_stderr(err_io) do
                            DistSSHKit.main(args)
                        end
                    end
                end
                flush(out_io)
                flush(err_io)
                return code, read(out_path, String), read(err_path, String)
            end
        end
    end

    let (code, _, err) = _main_capture(String[])
        @test code == 1
        @test occursin("Usage", err)
        @test occursin("julia -m DistSSHKit <command>", err)
    end
    # Unknown first token must fail, not exit 0.
    let (code, _, err) = _main_capture(["bogus"])
        @test code == 1
        @test occursin("Unknown subcommand: bogus", err)
    end
    let (code, _, err) = _main_capture(["rysnc", "host1"])
        @test code == 1
        @test occursin("Unknown subcommand: rysnc", err)
    end
    let (code, _, err) = _main_capture(["--help"])
        @test code == 0
        @test occursin("Usage", err)
        @test occursin("julia -m DistSSHKit <command>", err)
    end
    let (code, out, _) = _main_capture(["--version"])
        @test code == 0
        @test occursin("DistSSHKit $(DistSSHKit.dist_ssh_kit_version())", out)
    end
end
