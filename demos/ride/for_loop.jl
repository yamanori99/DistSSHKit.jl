#!/usr/bin/env julia
# Independent-looking `for` — `plan` reports out of scope (rewrite as map).
#
#   julia --project=. -m DistSSHKit plan demos/ride/for_loop.jl

xs = 1:4
ys = similar(collect(xs))
for i in eachindex(xs)
    ys[i] = xs[i] * xs[i]
end
println(join(ys, ","))
