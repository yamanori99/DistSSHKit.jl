# `DISTRIBUTED_SSH_OPTS` splitting. The run behavior is DistSSHRun's.

@testset "ssh_opts" begin
    withenv("DISTRIBUTED_SSH_OPTS" => "-F \"/tmp/cfg dir/config\" -o BatchMode=yes") do
        @test DistSSHKit.ssh_opts() == ["-F", "/tmp/cfg dir/config", "-o", "BatchMode=yes"]
    end
    withenv("DISTRIBUTED_SSH_OPTS" => "-F \"unterminated") do
        @test_throws ArgumentError DistSSHKit.ssh_opts()
    end
    withenv("DISTRIBUTED_SSH_OPTS" => nothing) do
        @test "BatchMode=yes" in DistSSHKit.ssh_opts()
    end
end
