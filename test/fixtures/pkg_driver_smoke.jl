# Driver for drive l:N smoke tests that call into an external package (JSON3).
using Distributed
using DistSSHKit
using JSON3

function init_output_dir!(_script_args::Vector{String})
    return DistSSHKit.resolve_distributed_output_dir!(_script_args, mktempdir())
end

function roundtrip_value(x::Int)
    return JSON3.read(JSON3.write(x), Int)
end

function main()
    vals = pmap(roundtrip_value, 1:4)
    for (i, v) in enumerate(vals)
        v == i || error("unexpected pmap result at ", i, ": ", v)
    end
    println("PKG_DRIVER_SMOKE_OK nw=", nworkers())
end
