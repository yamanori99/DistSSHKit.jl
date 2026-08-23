using Test
using Distributed

# Oracle: `measure_rss` with a local probe worker returns localhost samples
# with peak_gb >= baseline_gb. Does not assert a specific GB (rounding may
# hide ~8 MiB). Missing-probe throws stay in unit/DistSSHKit/size.jl.

@testset "measure_rss with probe (local)" begin
    _with_tempdir() do tmp
        write(joinpath(tmp, "Project.toml"), "name = \"ProbeTmp\"\nuuid = \"11111111-1111-1111-1111-111111111111\"\nversion = \"0.0.1\"\n")
        mkdir(joinpath(tmp, "src"))
        write(joinpath(tmp, "src", "ProbeTmp.jl"), "module ProbeTmp\nend\n")
        probe = joinpath(tmp, "warmup.jl")
        # ~8 MiB allocation — may or may not move rounded GB; peak >= baseline still holds.
        write(probe, "const _SIZE_WARMUP = zeros(Float64, 1_000_000)\n")
        samples = DistSSHKit.measure_rss(tmp, String[]; include_local=true, probe=probe)
        @test haskey(samples, "parenthost")
        s = samples["parenthost"]
        @test s.baseline_gb >= DistSSHKit.WORKER_MEMORY_GB_FLOOR
        @test s.peak_gb >= s.baseline_gb
        @test DistSSHKit.effective_worker_gb(s) == max(s.baseline_gb, s.peak_gb)
    end
end

@testset "measure_rss does not rmprocs pre-existing workers" begin
    _with_tempdir() do tmp
        write(joinpath(tmp, "Project.toml"), "name = \"ProbeKeep\"\nuuid = \"22222222-2222-2222-2222-222222222222\"\nversion = \"0.0.1\"\n")
        mkdir(joinpath(tmp, "src"))
        write(joinpath(tmp, "src", "ProbeKeep.jl"), "module ProbeKeep\nend\n")
        addprocs(1; topology=:master_worker)
        pre = workers()[end]
        try
            DistSSHKit.measure_rss(tmp, String[]; include_local=true)
            @test pre in workers()
        finally
            pre in workers() && rmprocs(pre; waitfor=2.0)
        end
    end
end

@testset "measure_rss removes its probe worker even when hosts is empty and include_local=false" begin
    _with_tempdir() do tmp
        write(joinpath(tmp, "Project.toml"), "name = \"ProbeNone\"\nuuid = \"33333333-3333-3333-3333-333333333333\"\nversion = \"0.0.1\"\n")
        mkdir(joinpath(tmp, "src"))
        write(joinpath(tmp, "src", "ProbeNone.jl"), "module ProbeNone\nend\n")
        before = Set(workers())
        samples = DistSSHKit.measure_rss(tmp, String[]; include_local=false)
        @test isempty(samples)
        # No probe worker requested: nothing added, nothing to remove.
        @test Set(workers()) == before
    end
end

@testset "measure_rss lone master leaves nprocs()==1 untouched" begin
    _with_tempdir() do tmp
        write(joinpath(tmp, "Project.toml"), "name = \"ProbeLone\"\nuuid = \"44444444-4444-4444-4444-444444444444\"\nversion = \"0.0.1\"\n")
        mkdir(joinpath(tmp, "src"))
        write(joinpath(tmp, "src", "ProbeLone.jl"), "module ProbeLone\nend\n")
        @test nprocs() == 1
        DistSSHKit.measure_rss(tmp, String[]; include_local=false)
        # No addprocs happened here, so the master must never be touched by
        # `_rmprocs_measure_probes!` (regression: it used to be possible to
        # target the whole cluster instead of just the probes it added).
        @test nprocs() == 1
        @test workers() == [1]
    end
end

@testset "measure_rss cleans up its own probe worker on package-load failure" begin
    _with_tempdir() do tmp
        # No Project.toml / package: probe still gets added and must still be
        # removed by the `finally` in `measure_rss`, even though sampling fails.
        before = Set(workers())
        samples = DistSSHKit.measure_rss(tmp, String[]; include_local=true)
        @test haskey(samples, "parenthost")
        @test Set(workers()) == before
    end
end
