#!/usr/bin/env julia
# DistSSHKit driver: pmap p→p² and print only (pair with square_file.jl).
#
#   julia --project=. -m DistSSHKit drive parenthost:2 demos/with_kit/square_echo.jl
#   julia --project=. -m DistSSHKit drive parenthost:2 demos/with_kit/square_echo.jl --n 4

using Distributed
using DistSSHKit

function _demo_n(args; default::Int)::Int
    n = default
    i = 1
    while i <= length(args)
        a = String(args[i])
        if a == "--n"
            i >= length(args) && throw(ArgumentError("--n needs an integer"))
            n = parse(Int, args[i + 1])
            i += 2
        elseif startswith(a, "--n=")
            n = parse(Int, chopprefix(a, "--n="))
            i += 1
        elseif a == "--output-dir"
            i >= length(args) && throw(ArgumentError("--output-dir needs a path"))
            i += 2
        else
            throw(ArgumentError(
                "unknown $(repr(a)); pass --n N (a bare number looks like parenthost:N)",
            ))
        end
    end
    n < 1 && throw(ArgumentError("--n must be ≥ 1, got $n"))
    return n
end

function init_output_dir!(_)
    DistSSHKit.resolve_distributed_output_dir!(ARGS, joinpath(@__DIR__, "output"))
end

function main()
    n = _demo_n(ARGS; default=8)
    results = pmap(p -> p^2, 1:n)
    println("param^2: ", results)
end
