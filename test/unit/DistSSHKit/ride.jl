using Test

@testset "ride" begin
    @testset "world age" begin
        let name = :_ride_world_age_probe_
            Core.eval(Main, :($name(x; k=0) = 2x + k))
            @test DistSSHKit._ride_main_call(name, 21) == 42
            @test DistSSHKit._ride_main_call(name, 10; k=3) == 23
        end
    end

    @testset "activate project" begin
        prev = Base.active_project()
        _with_tempdir() do tmp
            write(
                joinpath(tmp, "Project.toml"),
                """
                name = "RideAct"
                uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
                version = "0.1.0"
                """,
            )
            try
                DistSSHKit._ride_activate_project!(tmp)
                @test startswith(Base.active_project(), tmp)
            finally
                DistSSHKit._ride_restore_project!(prev)
            end
        end
        @test Base.active_project() == prev
    end

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

        fill = Meta.parse("for i in eachindex(xs); ys[i] = xs[i] * xs[i]; end")
        fr = DistSSHKit._ride_rewrite(fill)
        @test fr.head === :call
        @test fr.args[1] === GlobalRef(DistSSHKit, :_ride_index_fill!)
        @test !(fr.args[4] isa Expr && fr.args[4].head === :call &&
                fr.args[4].args[1] === :collect)

        acc = Meta.parse("for x in xs; s += x; end")
        @test DistSSHKit._ride_rewrite(acc).head === :for

        stencil = Meta.parse("for i in 2:length(dest); dest[i] = alias[i - 1]; end")
        @test DistSSHKit._ride_rewrite(stencil).head === :for

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
        @test r.output_dir !== nothing
        @test !isfile(joinpath(something(r.output_dir, ""), "kit.hosts"))
        st = DistSSHKit.drive_host_status(something(r.output_dir, ""))
        @test any(row -> row.host == DistSSHKit.PARENT_HOST_NAME, st)

        _with_tempdir() do hosts_tmp
            DistSSHKit._write_kit_hosts_file(["alice@h1", "bob@h2"], hosts_tmp, nothing)
            @test DistSSHKit._read_kit_hosts(hosts_tmp) == ["alice@h1", "bob@h2"]
        end

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

        loop = joinpath(tmp, "loop.jl")
        lout = joinpath(tmp, "loop.txt")
        write(loop, """
            xs = 1:4
            ys = similar(collect(xs))
            for i in eachindex(xs)
                ys[i] = xs[i] * xs[i]
            end
            write($(repr(lout)), join(string.(ys), ","))
            """)
        rl = DistSSHKit.ride!(loop, "parent:1"; spi_check=true)
        @test rl.ok
        @test rl.spi_ok !== false
        @test read(lout, String) == "1,4,9,16"

        st_path = joinpath(tmp, "stateful.jl")
        stout = joinpath(tmp, "stateful.txt")
        write(st_path, """
            xs = [1, 2, 3, 4]
            ys = similar(xs)
            for i in Iterators.Stateful(eachindex(xs))
                ys[i] = xs[i] * xs[i]
            end
            write($(repr(stout)), join(string.(ys), ","))
            """)
        rs = DistSSHKit.ride!(st_path, "parent:1"; spi_check=false)
        @test rs.ok
        @test read(stout, String) == "1,4,9,16"

        alias_path = joinpath(tmp, "alias.jl")
        aout = joinpath(tmp, "alias.txt")
        write(alias_path, """
            dest = [1, 2, 3]
            alias = dest
            for i in 2:length(dest)
                dest[i] = alias[i - 1]
            end
            write($(repr(aout)), join(string.(dest), ","))
            """)
        ra = DistSSHKit.ride!(alias_path, "parent:1"; spi_check=false)
        @test ra.ok
        @test read(aout, String) == "1,1,1"

        obs_path = joinpath(tmp, "observe.jl")
        oout = joinpath(tmp, "observe.txt")
        write(obs_path, """
            dest = [1, 2, 3]
            seen = Int[]
            observe(i) = (push!(seen, dest[1]); 0)
            for i in eachindex(dest)
                dest[i] = observe(i)
            end
            write($(repr(oout)), join(string.(seen), ",") * ";" * join(string.(dest), ","))
            """)
        ro = DistSSHKit.ride!(obs_path, "parent:1"; spi_check=false)
        @test ro.ok
        @test read(oout, String) == "1,0,0;0,0,0"

        gen_path = joinpath(tmp, "geniter.jl")
        gout = joinpath(tmp, "geniter.txt")
        write(gen_path, """
            dest = zeros(Int, 3)
            n = Ref(0)
            struct _RideUnknownIter
                n::Ref{Int}
            end
            Base.IteratorSize(::Type{_RideUnknownIter}) = Base.SizeUnknown()
            function Base.iterate(it::_RideUnknownIter, st=1)
                st > 3 && return nothing
                it.n[] += 1
                return (st, st + 1)
            end
            for i in _RideUnknownIter(n)
                dest[i] = n[]
            end
            write($(repr(gout)), join(string.(dest), ","))
            """)
        rg = DistSSHKit.ride!(gen_path, "parent:1"; spi_check=false)
        @test rg.ok
        @test read(gout, String) == "1,2,3"

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
