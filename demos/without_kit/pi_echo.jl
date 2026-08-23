#!/usr/bin/env julia
# Kit-independent job — no DistSSHKit, no file output (demos/without_kit/).
#
# Monte Carlo π estimate; prints only (pair with pi_file.jl).
#
#   julia demos/without_kit/pi_echo.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_echo.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_echo.jl --n 5000

using Random

function _demo_n(args; default::Int)::Int
    n = default
    i = 1
    while i <= length(args)
        a = String(args[i])
        if a == "--n"
            i >= length(args) && throw(ArgumentError("--n needs an integer"))
            n = parse(Int, args[i + 1])
            i += 2
        elseif startswith(a, "--n=")
            n = parse(Int, chopprefix(a, "--n="))
            i += 1
        else
            throw(ArgumentError(
                "unknown $(repr(a)); pass --n N (a bare number looks like parenthost:N)",
            ))
        end
    end
    n < 1 && throw(ArgumentError("--n must be ≥ 1, got $n"))
    return n
end

function main()
    n = _demo_n(ARGS; default=1000)
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
