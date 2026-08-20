# Long enough for E2E to kill the master and watch heartbeat reap workers.
using Distributed

function main()
    pmap(_ -> (sleep(30); 1), 1:nworkers())
    return nothing
end
