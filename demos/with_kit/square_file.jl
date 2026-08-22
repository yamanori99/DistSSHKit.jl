#!/usr/bin/env julia
# DistSSHKit driver: pmap p→p² and write CSV (pair with square_echo.jl).
#
#   julia --project=. -m DistSSHKit drive parenthost:4 demos/with_kit/square_file.jl
#   julia --project=. -m DistSSHKit drive parenthost:4 demos/with_kit/square_file.jl 4

using Distributed
using DistSSHKit

function init_output_dir!(_)
    DistSSHKit.resolve_distributed_output_dir!(ARGS, joinpath(@__DIR__, "output"))
end

function main()
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 8
    results = pmap(p -> p^2, 1:n)

    out_path = joinpath(ENV["DISTRIBUTED_OUTPUT_DIR"], "square_results.csv")
    text = "param,result\n"
    for i in 1:n
        text *= "$i,$(results[i])\n"
    end
    write(out_path, text)
    println("wrote ", out_path)
end
