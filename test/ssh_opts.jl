# `DISTRIBUTED_SSH_OPTS` splitting. The run behavior is DistSSHRun's.

@testset "ssh_opts" begin
    withenv("DISTRIBUTED_SSH_OPTS" => "-F \"/tmp/cfg dir/config\" -o BatchMode=yes") do
        vec = DistSSHKit.ssh_opts()
        @test vec[1:2] == ["-F", "/tmp/cfg dir/config"]
        @test count(==("BatchMode=yes"), vec) == 1
        @test "ExitOnForwardFailure=yes" in vec
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-F \"unterminated") do
        @test_throws ArgumentError DistSSHKit.ssh_opts()
    end
    withenv("DISTRIBUTED_SSH_OPTS" => nothing) do
        @test "BatchMode=yes" in DistSSHKit.ssh_opts()
    end
end
