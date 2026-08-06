# Minimal driver for `drive l:N` smoke tests (spawned as a subprocess).
using Distributed

function main()
    nw = nworkers()
    nw >= 2 || error("expected >= 2 workers, got ", nw)
    println("DISTSSHKIT_RUNNER_SMOKE_OK nw=", nw)
end
