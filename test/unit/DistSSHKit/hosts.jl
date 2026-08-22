using Test

@testset "hosts helpers" begin
    @testset "is_local_host_name" begin
        @test DistSSHKit.is_local_host_name("parenthost")
        @test DistSSHKit.is_local_host_name("local")
        @test DistSSHKit.is_local_host_name("localhost")
        @test DistSSHKit.is_local_host_name("l")
        @test DistSSHKit.is_deprecated_local_host_name("local")
        @test !DistSSHKit.is_deprecated_local_host_name("parenthost")
        @test !DistSSHKit.is_local_host_name("root@192.0.2.10")
        @test !DistSSHKit.is_local_host_name("worker-node-a")
        DistSSHKit._reset_deprecated_local_host_warning!()
        @test_logs (:warn, r"0\.4") DistSSHKit.warn_deprecated_local_host!()
        @test_nowarn DistSSHKit.warn_deprecated_local_host!()  # once per process
        DistSSHKit._reset_deprecated_local_host_warning!()
        @test_nowarn DistSSHKit.parse_worker_tokens(["parenthost:1"])
        DistSSHKit._reset_deprecated_local_host_warning!()
        @test_logs (:warn, r"parenthost") DistSSHKit.parse_worker_tokens(["local:1"])
    end

    @testset "looks_like_path_host / script" begin
        @test DistSSHKit.looks_like_script_host("script.jl")
        @test DistSSHKit.looks_like_script_host("demos/foo.JL")
        @test DistSSHKit.looks_like_path_host("demos/orchestration/my_sim.jl")
        @test DistSSHKit.looks_like_path_host("relative/path")
        @test !DistSSHKit.looks_like_path_host("root@192.0.2.10")
        @test !DistSSHKit.looks_like_path_host("user@host:22")  # colon ok; @ present
        @test !DistSSHKit.looks_like_path_host("worker-node-a")
        _with_tempdir() do tmp
            cd(tmp) do
                write("worker-node-a", "")
                @test DistSSHKit.looks_like_path_host("worker-node-a")
            end
        end
    end

    @testset "summarize_ssh_error" begin
        usekey = ErrorException("/Users/x/.ssh/config: line 27: Bad configuration option: usekeychain")
        msg = DistSSHKit.summarize_ssh_error(usekey)
        @test occursin("UseKeychain", msg)
        @test occursin("IgnoreUnknown", msg)

        auth = ErrorException("Permission denied (publickey).")
        @test occursin("ssh-copy-id", DistSSHKit.summarize_ssh_error(auth))

        dns = ErrorException("Could not resolve hostname foo: nodename nor servname provided")
        @test occursin("not found", DistSSHKit.summarize_ssh_error(dns))

        timed = ErrorException("Connection timed out")
        @test occursin("timeout", DistSSHKit.summarize_ssh_error(timed))

        via_stderr = DistSSHKit.summarize_ssh_error(
            ErrorException("failed process"),
            stderr="Bad configuration option: usekeychain\nterminating",
        )
        @test occursin("IgnoreUnknown", via_stderr)

        short = DistSSHKit.summarize_ssh_error(
            ErrorException("x");
            stderr="only stderr line",
        )
        @test short == "only stderr line"
    end
end
