#!/usr/bin/env julia
# Meta-package checks. The run surface is tested in DistSSHRun, the queue in
# DistSSHQueue. This suite checks reexports and `julia -m DistSSHKit` routing.

using Test
using DistSSHKit
using DistSSHQueue
using DistSSHRun

function _main_capture(args)
    return mktemp() do out_path, out_io
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

@testset "DistSSHKit" verbose = true begin
    @testset "reexport" begin
        for n in names(DistSSHRun)
            n === :DistSSHRun && continue
            n === :println_kit_version && continue
            @test isdefined(DistSSHKit, n)
            @test getproperty(DistSSHKit, n) === getproperty(DistSSHRun, n)
            @test n in names(DistSSHKit)
        end
        for n in names(DistSSHQueue)
            n === :DistSSHQueue && continue
            @test isdefined(DistSSHKit, n)
            @test getproperty(DistSSHKit, n) === getproperty(DistSSHQueue, n)
            @test n in names(DistSSHKit)
        end
        @test !isdefined(DistSSHKit, :_read_kit_pid_record)
        @test !isdefined(DistSSHKit, :_juliaup_default_channel_from_status)
        @test DistSSHKit.dist_ssh_kit_version() == v"0.9.0"
        @test DistSSHKit.dist_ssh_kit_version() != DistSSHRun.dist_ssh_kit_version()
        @test DistSSHKit.go! === DistSSHRun.go!
        @test DistSSHKit.submit! === DistSSHQueue.submit!
    end

    @testset "main" begin
        let (code, _, err) = _main_capture(String[])
            @test code == 1
            @test occursin("Usage", err)
            @test occursin("julia -m DistSSHKit <command>", err)
            @test occursin("submit", err)
        end
        let (code, _, err) = _main_capture(["bogus"])
            @test code == 1
            @test occursin("Unknown subcommand: bogus", err)
            @test occursin("submit", err)
        end
        let (code, _, err) = _main_capture(["map_echo.jl"])
            @test code == 1
            @test occursin("does not infer go / ride / drive", err)
            @test occursin("go SCRIPT.jl", err)
            @test !occursin("Unknown subcommand", err)
        end
        let (code, _, err) = _main_capture(["parent:2", "job.jl"])
            @test code == 1
            @test occursin("does not infer go / ride / drive", err)
        end
        let (code, out, err) = _main_capture(["--help"])
            @test code == 0
            @test occursin("Usage", err)
            @test occursin("progress", err)
            @test occursin("submit", err)
            @test isempty(out)
        end
        let (code, out, _) = _main_capture(["--version"])
            @test code == 0
            @test out == "DistSSHKit $(DistSSHKit.dist_ssh_kit_version())\n"
        end
        let (code, out, _) = _main_capture(["go", "--version"])
            @test code == 0
            @test out == "DistSSHKit $(DistSSHKit.dist_ssh_kit_version())\n"
        end
        let (code, out, err) = _main_capture(["go", "--help"])
            combined = out * err
            @test code == 0
            @test occursin("Usage", combined)
        end
        let (code, out, err) = _main_capture(["setup", "--help"])
            combined = out * err
            @test code == 0
            @test occursin("clone", lowercase(combined))
        end
        let (code, out, err) = _main_capture(["submit", "--help"])
            combined = out * err
            @test code == 0
            @test occursin("submit", lowercase(combined))
        end
        let (code, out, err) = _main_capture(["--help", "client"])
            combined = out * err
            @test code == 0
            @test occursin("submit", lowercase(combined))
            @test occursin("Jobs", combined)
        end
        let (code, out, err) = _main_capture(["qhost:HOST", "submit", "--help"])
            combined = out * err
            @test code == 0
            @test occursin("submit", lowercase(combined))
            @test !occursin("could not resolve hostname", lowercase(combined))
        end
    end
end
