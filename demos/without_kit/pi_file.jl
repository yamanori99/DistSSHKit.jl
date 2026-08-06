#!/usr/bin/env julia
# Kit-independent job — no DistSSHKit (demos/without_kit/).
#
# Monte Carlo π estimate; writes pi_results.txt (pair with pi_echo.jl).
#
#   julia demos/without_kit/pi_file.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl 5000

using Random

function main()
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1000

    env = strip(get(ENV, "DISTRIBUTED_OUTPUT_DIR", ""))
    outdir = isempty(env) ? joinpath(@__DIR__, "output") : env
    mkpath(outdir)

    Random.seed!(42)

    inside = 0
    for _ in 1:n
        x, y = rand(), rand()
        if x * x + y * y <= 1.0
            inside += 1
        end
    end
    pi_hat = 4.0 * inside / n

    out_path = joinpath(outdir, "pi_results.txt")
    write(out_path, "n=$n inside=$inside pi=$pi_hat\n")

    println("π ≈ $pi_hat  (inside=$inside / n=$n)")
    println("wrote ", relpath(out_path, @__DIR__))
end

main()
