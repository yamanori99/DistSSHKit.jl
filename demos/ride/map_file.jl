#!/usr/bin/env julia
# Plain script: map and write CSV (pair with map_echo.jl).
#
#   julia --project=. -m DistSSHKit ride parent:2 demos/ride/map_file.jl

function work(x)
    return x * x
end

xs = 1:8
ys = map(work, xs)

env = strip(get(ENV, "DISTRIBUTED_OUTPUT_DIR", ""))
outdir = isempty(env) ? joinpath(@__DIR__, "output") : env
mkpath(outdir)
out_path = joinpath(outdir, "map_results.csv")
open(out_path, "w") do io
    println(io, "x,y")
    for (x, y) in zip(xs, ys)
        println(io, x, ",", y)
    end
end
println("wrote ", out_path)
