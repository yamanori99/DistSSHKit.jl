#!/usr/bin/env julia
# Independent indexed `for` (`dest[i] = …`). `plan` suggests ride.
#
#   julia --project=. -m DistSSHKit plan demos/ride/for_loop.jl
#   julia --project=. -m DistSSHKit ride parent:2 demos/ride/for_loop.jl

xs = 1:4
ys = similar(collect(xs))
for i in eachindex(xs)
    ys[i] = xs[i] * xs[i]
end
println(join(ys, ","))
