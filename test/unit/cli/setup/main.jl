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
    let (code, combined_out, combined_err) = begin
            code, out, err = _setup_capture(["--delete", "local"])
            (code, out, err)
        end
        @test code == 1
        txt = combined_out * combined_err
        @test occursin("SSH targets only", txt)
    end
end
