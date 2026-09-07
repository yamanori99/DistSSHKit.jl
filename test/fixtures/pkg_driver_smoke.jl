# Driver for drive l:N smoke tests that call into an external package (JSON).
using Distributed
using DistSSHKit
using JSON

function init_output_dir!(_script_args::Vector{String})
    return DistSSHKit.resolve_distributed_output_dir!(_script_args, mktempdir())
end

function roundtrip_value(x::Int)
    return JSON.parse(JSON.json(x), Int)
end

function main()
    vals = pmap(roundtrip_value, 1:4)
    for (i, v) in enumerate(vals)
        v == i || error("unexpected pmap result at ", i, ": ", v)
    end
    return println("PKG_DRIVER_SMOKE_OK nw=", nworkers())
end
