# Driver that chooses its own artifact dir (no DistSSHKit import).
using Distributed

function init_output_dir!(args)
    dest = joinpath(dirname(@__FILE__), "user_out")
    if length(args) >= 2 && args[1] == "--out"
        dest = args[2]
    end
    ENV["DISTRIBUTED_OUTPUT_DIR"] = dest
    mkpath(dest)
    return nothing
end

function main()
    out = ENV["DISTRIBUTED_OUTPUT_DIR"]
    write(joinpath(out, "hook.txt"), "ok\n")
    println("DISTSSHKIT_INIT_OUTPUT_OK ", out)
    return nothing
end
