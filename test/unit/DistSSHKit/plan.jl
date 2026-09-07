using Test

@testset "plan" begin
    _with_tempdir() do tmp
        map_path = joinpath(tmp, "mapped.jl")
        write(map_path, """
            f(x) = x + 1
            map(f, 1:8)
            """)
        kp = DistSSHKit.plan(map_path)
        @test kp.ok
        @test kp.suggest === :ride
        @test any(f -> f.kind === :map && f.status === :candidate, kp.findings)
        @test kp.julia == string(VERSION)
        @test :plan! ∉ names(DistSSHKit)

        filt_path = joinpath(tmp, "filt.jl")
        write(filt_path, "filter(iseven, 1:10)\n")
        @test DistSSHKit.plan(filt_path).suggest === :ride

        comp_path = joinpath(tmp, "comp.jl")
        write(comp_path, "ys = [x^2 for x in 1:4]\n")
        kc = DistSSHKit.plan(comp_path)
        @test kc.suggest === :ride
        @test any(f -> f.kind === :comprehension, kc.findings)

        for_path = joinpath(tmp, "loop.jl")
        write(for_path, """
            xs = 1:3
            results = similar(collect(xs))
            for i in eachindex(xs)
                results[i] = xs[i]
            end
            """)
        kf = DistSSHKit.plan(for_path)
        @test kf.suggest === :ride
        @test any(f -> f.kind === :for && f.status === :candidate, kf.findings)
        buf = IOBuffer()
        DistSSHKit.print_plan(kf; io=buf)
        @test occursin("suggest:  ride", String(take!(buf)))

        acc_path = joinpath(tmp, "acc.jl")
        write(acc_path, """
            s = 0
            for x in 1:3
                s += x
            end
            """)
        ka = DistSSHKit.plan(acc_path)
        @test ka.suggest === :go
        @test any(f -> f.kind === :for && f.status === :out_of_scope, ka.findings)

        stenc_path = joinpath(tmp, "stenc.jl")
        write(stenc_path, """
            dest = [1, 2, 3]
            alias = dest
            for i in 2:length(dest)
                dest[i] = alias[i - 1]
            end
            """)
        ks = DistSSHKit.plan(stenc_path)
        @test ks.suggest === :go
        @test any(f -> f.kind === :for && f.status === :out_of_scope, ks.findings)

        drive_path = joinpath(tmp, "driver.jl")
        write(drive_path, """
            using Distributed
            pmap(x -> x^2, 1:4)
            """)
        kd = DistSSHKit.plan(drive_path)
        @test kd.suggest === :drive
        @test any(f -> f.status === :drive_vocab, kd.findings)

        every_path = joinpath(tmp, "every.jl")
        write(every_path, "@everywhere foo() = 1\n")
        @test DistSSHKit.plan(every_path).suggest === :drive

        plain_path = joinpath(tmp, "plain.jl")
        write(plain_path, "println(2 + 2)\n")
        @test DistSSHKit.plan(plain_path).suggest === :go

        missing = DistSSHKit.plan(joinpath(tmp, "nope.jl"))
        @test !missing.ok
        @test occursin("file not found", missing.error)
        @test missing.slots === nothing

        @test DistSSHKit.plan(map_path).slots === nothing
        sized = with_kit_verbosity(:progress) do
            DistSSHKit.plan(
                map_path;
                workers=["parent"],
                project=tmp,
                gb_per_worker=2.0,
            )
        end
        @test sized.ok
        @test sized.suggest === :ride
        @test sized.slots isa DistSSHKit.WorkerPlan
        local_total, local_nproc = DistSSHKit.get_local_resources()
        @test sized.slots.parent_workers == DistSSHKit.size_worker_count(
            local_total, local_nproc, 2.0; is_parent=true,
        )
        buf2 = IOBuffer()
        DistSSHKit.print_plan(sized; io=buf2)
        @test occursin("slots:", String(take!(buf2)))
    end
end
