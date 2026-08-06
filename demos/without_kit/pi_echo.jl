#!/usr/bin/env julia
# Kit-independent job — no DistSSHKit, no file output (demos/without_kit/).
#
# Monte Carlo π estimate; prints only (pair with pi_file.jl).
#
#   julia demos/without_kit/pi_echo.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_echo.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_echo.jl 5000

using Random

function main()
    n = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1000
    Random.seed!(42)

    inside = 0
    for _ in 1:n
        x, y = rand(), rand()
        if x * x + y * y <= 1.0
            inside += 1
        end
    end
    pi_hat = 4.0 * inside / n
    println("π ≈ $pi_hat  (inside=$inside / n=$n)")
end

main()
