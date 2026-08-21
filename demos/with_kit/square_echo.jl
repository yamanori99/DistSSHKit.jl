#!/usr/bin/env julia
# DistSSHKit driver: pmap p→p² and print only (pair with square_file.jl).
#
#   julia --project=. -m DistSSHKit drive masterhost:4 demos/with_kit/square_echo.jl
#   julia --project=. -m DistSSHKit drive masterhost:4 demos/with_kit/square_echo.jl 4

using Distributed
using DistSSHKit

function init_output_dir!(_)
    DistSSHKit.resolve_distributed_output_dir!(ARGS, joinpath(@__DIR__, "output"))
end

function main()
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8
    results = pmap(p -> p^2, 1:n)
    println("param^2: ", results)
end
