# Reexports. Not a guarantee that a future dependency export is wanted.

@testset "reexport" begin
    for n in names(DistSSHRun)
        n === :DistSSHRun && continue
        n === :println_kit_version && continue
        @test isdefined(DistSSHKit, n)
        @test n in names(DistSSHKit)
        @test getproperty(DistSSHKit, n) === getproperty(DistSSHRun, n)
    end
    for n in names(DistSSHQueue)
        n === :DistSSHQueue && continue
        @test isdefined(DistSSHKit, n)
        @test getproperty(DistSSHKit, n) === getproperty(DistSSHQueue, n)
        @test n in names(DistSSHKit)
    end
    @test !isdefined(DistSSHKit, :_read_kit_pid_record)
    @test !isdefined(DistSSHKit, :_juliaup_default_channel_from_status)
    @test DistSSHKit.go! === DistSSHRun.go!
    @test DistSSHKit.submit! === DistSSHQueue.submit!
end

@testset "export surface" begin
    allowed = Set(
        [
            names(DistSSHRun); names(DistSSHQueue);
            :DistSSHKit; :println_kit_version
        ]
    )
    @test Set(names(DistSSHKit)) ⊆ allowed
    for n in DistSSHKit._OWN
        @test Base.binding_module(DistSSHKit, n) === DistSSHKit
    end
    @test DistSSHKit.println_kit_version !== DistSSHRun.println_kit_version
    for n in DistSSHKit._QUALIFIED
        @test isdefined(DistSSHKit, n)
    end
end
