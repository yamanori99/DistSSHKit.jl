using Test

# Oracle: in-process `setup` CLI entry (`src/cli/setup.jl`) for help-like
# modes and host-validation failure. Fake ssh/rsync success paths stay in
# integration/setup/exit.jl.

@testset "setup CLI entry" begin
    function _setup_capture(args)
        mktemp() do out_path, out_io
            mktemp() do err_path, err_io
                code = withenv("DISTSSHKIT_CLI_SUBCOMMAND_DONE" => "") do
                    redirect_stdout(out_io) do
                        redirect_stderr(err_io) do
                            DistSSHKit.setup(args)
                        end
                    end
                end
                flush(out_io)
                flush(err_io)
                return code, read(out_path, String), read(err_path, String)
            end
        end
    end

    let (code, out, _) = _setup_capture(String[])
        @test code == 0
        @test occursin("Recommended", out)
        @test occursin("--rsync", out)
    end
    let (code, out, _) = _setup_capture(["--requirements"])
        @test code == 0
        @test occursin("--instantiate", out)
    end
    let (code, out, err) = _setup_capture(["--delete", "parent"])
        @test code == 1
        @test occursin("only for --juliaup", out * err)
    end
    let (code, out, err) = _setup_capture(["--delete", "host1"])
        @test code == 1
        combined = out * err
        @test occursin("child:NAME", combined) || occursin("parent[:N]", combined)
    end
end
