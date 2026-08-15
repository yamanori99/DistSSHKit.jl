using Test

# Oracle: `go!(…, "local:2")` runs two local slots concurrently (slot t0.txt
# timestamps within 0.45s). Does not cover SSH, CLI `go`, or slot-plan math
# (those live in unit/DistSSHKit/go.jl).

@testset "local slots overlap" begin
    _with_tempdir() do proj
        write(joinpath(proj, "Project.toml"), "name = \"GoOverlap\"\n")
        script = joinpath(proj, "sleep_mark.jl")
        write(script, """
            out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", ".")
            mkpath(out)
            write(joinpath(out, "t0.txt"), string(time()))
            sleep(0.6)
            """)
        t0 = time()
        result = DistSSHKit.go!(
            script,
            "local:2";
            project=proj,
            quiet=true,
            yes=true,
        )
        wall = time() - t0
        @test result.ok
        a = parse(Float64, read(joinpath(result.output_dir, "local-1", "t0.txt"), String))
        b = parse(Float64, read(joinpath(result.output_dir, "local-2", "t0.txt"), String))
        @test abs(a - b) < 0.45  # sequential would be ~0.6s apart plus julia startup
        @test wall < 8.0
    end
end
