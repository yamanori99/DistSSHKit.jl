using Test

# Oracle: `measure_rss` with a local probe worker returns localhost samples
# with peak_gb >= baseline_gb. Does not assert a specific GB (rounding may
# hide ~8 MiB). Missing-probe throws stay in unit/DistSSHKit/size.jl.

@testset "measure_rss with probe (local)" begin
    _with_tempdir() do tmp::String
        write(joinpath(tmp, "Project.toml"), "name = \"ProbeTmp\"\nuuid = \"11111111-1111-1111-1111-111111111111\"\nversion = \"0.0.1\"\n")
        mkdir(joinpath(tmp, "src"))
        write(joinpath(tmp, "src", "ProbeTmp.jl"), "module ProbeTmp\nend\n")
        probe = joinpath(tmp, "warmup.jl")
        # ~8 MiB allocation — may or may not move rounded GB; peak >= baseline still holds.
        write(probe, "const _SIZE_WARMUP = zeros(Float64, 1_000_000)\n")
        samples = DistSSHKit.measure_rss(tmp, String[]; include_local=true, probe=probe)
        @test haskey(samples, "localhost")
        s = samples["localhost"]
        @test s.baseline_gb >= DistSSHKit.WORKER_MEMORY_GB_FLOOR
        @test s.peak_gb >= s.baseline_gb
        @test DistSSHKit.effective_worker_gb(s) == max(s.baseline_gb, s.peak_gb)
    end
end
