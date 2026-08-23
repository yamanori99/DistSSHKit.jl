#!/usr/bin/env julia
# Kit-independent job — no DistSSHKit (demos/without_kit/).
#
# Monte Carlo π estimate; writes pi_results.txt (pair with pi_echo.jl).
#
#   julia demos/without_kit/pi_file.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl
#   julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl --n 5000

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
