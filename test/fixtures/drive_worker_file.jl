# Write a file on each SSH worker (not on the controller).
# square_file.jl writes CSV in main() on the controller; this is for collect bytes.

using Distributed
using DistSSHKit

function init_output_dir!(_)
    DistSSHKit.resolve_distributed_output_dir!(ARGS, joinpath(@__DIR__, "output"))
end

function write_worker_file()
    dir = joinpath(@__DIR__, "output")
    mkpath(dir)
    path = joinpath(dir, "worker_$(myid()).txt")
    write(path, "DISTSSHKIT_E2E_WORKER_FILE id=$(myid())\n")
    return path
end

function main()
    for w in workers()
        remotecall_fetch(write_worker_file, w)
    end
end
