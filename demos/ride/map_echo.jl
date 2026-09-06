#!/usr/bin/env julia
# Plain script for `plan` / `go` / `ride` (no Distributed).
#
#   julia demos/ride/map_echo.jl
#   julia --project=. -m DistSSHKit plan demos/ride/map_echo.jl
#   julia --project=. -m DistSSHKit ride parent:2 demos/ride/map_echo.jl

function work(x)
    return x * x
end

xs = 1:8
ys = map(work, xs)
println(join(ys, ","))
