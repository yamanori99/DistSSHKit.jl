#!/usr/bin/env julia
# Plain script: filter (ride candidate).
#
#   julia --project=. -m DistSSHKit ride parent:2 demos/ride/filter_echo.jl

xs = 1:10
ys = filter(iseven, xs)
println(join(ys, ","))
