# Sleep on workers so E2E can terminate! a detached SSH ride.
map(x -> (sleep(30); x), 1:4)
