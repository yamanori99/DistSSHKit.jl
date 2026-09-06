using Test

@testset "ride" begin
    @testset "rewrite" begin
        ex = Meta.parse("map(f, xs)")
        rw = DistSSHKit._ride_rewrite(ex)
        @test rw.head === :call
        @test rw.args[1] === GlobalRef(DistSSHKit, :_ride_map)
        @test rw.args[2].head === :call
        @test rw.args[2].args[1] === GlobalRef(DistSSHKit, :_ride_named_fn)

        fx = Meta.parse("filter(iseven, xs)")
        @test DistSSHKit._ride_rewrite(fx).args[1] === GlobalRef(DistSSHKit, :_ride_filter)

        mx2 = Meta.parse("map(+, xs, ys)")
        @test DistSSHKit._ride_rewrite(mx2).args[1] === :map

        cx = Meta.parse("[x^2 for x in xs]")
        cr = DistSSHKit._ride_rewrite(cx)
        @test cr.args[1] === GlobalRef(DistSSHKit, :_ride_map)

        fx2 = Meta.parse("for i in xs; f(i); end")
        @test DistSSHKit._ride_rewrite(fx2).head === :for

        pre = DistSSHKit._ride_worker_prelude(Meta.parseall("""
            function work(x)
                x + 1
            end
            ys = map(work, 1:3)
            """))
        s = string(pre)
        @test occursin("work", s)
        @test !occursin("map", s)

        plan = DistSSHKit._ride_resolve_plan(
            ["child:h:2", "parent:1"];
            session=nothing,
            gb_per_worker=nothing,
            probe=nothing,
            mem_headroom=DistSSHKit.DEFAULT_MEM_HEADROOM,
            parent_gb=DistSSHKit.DEFAULT_PARENT_GB,
        )
        @test plan.parent_workers == 1
        @test plan.child_workers["h"] == 2

        _with_tempdir() do tmp
            script = joinpath(tmp, "map.jl")
            d1 = DistSSHKit._ride_batch_dir(script, nothing; project=tmp)
            d2 = DistSSHKit._ride_batch_dir(script, nothing; project=tmp)
            @test isdir(d1) && isdir(d2)
            @test d1 != d2
        end
    end

    @testset "kit_run_result" begin
        r = DistSSHKit.RideResult(true, "s.jl", 2, true, nothing, "1.13")
        kr = DistSSHKit.kit_run_result(r)
        @test kr.ok
        @test kr.kind === :ride
        @test kr.exit_code == 0
        @test kr.failed_step === nothing
        bad = DistSSHKit.RideResult(false, "s.jl", 0, nothing, "boom", "1.13")
        @test DistSSHKit.kit_run_result(bad).failed_step == "ride"
    end

    _with_tempdir() do tmp
        out = joinpath(tmp, "out.txt")
        map_path = joinpath(tmp, "mapped.jl")
        write(map_path, """
            ys = map(x -> x + 1, 1:4)
            write($(repr(out)), join(string.(ys), ","))
            """)
        r = DistSSHKit.ride!(map_path, "parent:1"; spi_check=true)
        @test r.ok
        @test r.workers == 1
        @test r.spi_ok === true
        @test read(out, String) == "2,3,4,5"

        fout = joinpath(tmp, "filt.txt")
        filt = joinpath(tmp, "filt.jl")
        write(filt, """
            ys = filter(iseven, 1:6)
            write($(repr(fout)), join(string.(ys), ","))
            """)
        rf = DistSSHKit.ride!(filt, "parent:1"; spi_check=true)
        @test rf.ok
        @test read(fout, String) == "2,4,6"

        named = joinpath(tmp, "named.jl")
        nout = joinpath(tmp, "named.txt")
        write(named, """
            function work(x)
                x * x
            end
            ys = map(work, 1:3)
            write($(repr(nout)), join(string.(ys), ","))
            """)
        rn = DistSSHKit.ride!(named, "parent:1"; spi_check=true)
        @test rn.ok
        @test read(nout, String) == "1,4,9"

        child = DistSSHKit.ride!(map_path, "child:host1")
        @test !child.ok
        @test occursin("KitSession", something(child.error, ""))

        drive_path = joinpath(tmp, "driver.jl")
        write(drive_path, "using Distributed\npmap(x -> x, 1:2)\n")
        rd = DistSSHKit.ride!(drive_path)
        @test !rd.ok
        @test occursin("drive", something(rd.error, ""))
        @test occursin("pmap", something(rd.error, ""))

        buf = IOBuffer()
        DistSSHKit.print_ride(r; io=buf)
        shown = String(take!(buf))
        @test startswith(shown, "DistSSHKit ride\n")
        @test occursin("Script: ", shown)
        @test occursin("Workers: ", shown)
        @test occursin("Julia: ", shown)
        @test occursin("DistSSHKit: ", shown)
        @test occursin("SPI check: passed", shown)
        @test !occursin("Ride:", shown)
    end
end
