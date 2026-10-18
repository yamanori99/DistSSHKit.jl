# Stdlib only. The package demo loads DistSSHRun on the workers, which a
# runner without that project installed cannot do.
using Distributed

function main()
    println(pmap(x -> x * x, 1:4))
end
