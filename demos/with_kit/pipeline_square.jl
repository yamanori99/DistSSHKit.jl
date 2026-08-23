#!/usr/bin/env julia
# DistSSHKit API demo: run square_file.jl through `pipeline!`
# (optional sync → size! → drive! → collect) instead of the `drive` CLI.
#
# Local (this script):
#
#   julia --project=. demos/with_kit/pipeline_square.jl
#   julia --project=. demos/with_kit/pipeline_square.jl --n 4
#
# Same driver via CLI:
#
#   julia --project=. -m DistSSHKit drive parenthost:2 demos/with_kit/square_file.jl --n 4

using DistSSHKit

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

driver = joinpath(@__DIR__, "square_file.jl")
n = string(_demo_n(ARGS; default=8))

# Local-only: two Distributed workers on this machine (collect off — outputs stay local).
result = pipeline!(driver, "parenthost:2"; args=["--n", n], collect=false, enable_log=false)

# First-time remotes: setup!, then pipeline! (or drive!).
#
#   session = KitSession(
#       workers=["user@host1", "user@host2"],
#       remote="/path/to/project",
#       yes=true,
#   )
#   setup!(session, :rsync, :instantiate)
#   # or: setup!(session, :clone; repo="https://…"); setup!(session, :instantiate)
#   result = pipeline!(
#       driver,
#       "user@host1:1",
#       "user@host2:1";
#       remote="/path/to/project",
#       args=["--n", n],
#       # julia=nothing,                  # or path / "auto" (same as CLI --julia)
#   )
#
# Other `pipeline!` keywords (uncomment / edit as needed):
#
#   result = pipeline!(
#       driver,
#       "user@host1:1",
#       "user@host2:1";   # or pipeline!(driver, ["user@host1:1", …]; …)
#       remote="/path/to/project",
#       args=["--n", n],
#       collect=true,                   # false → skip; path → collect root
#       # project=pwd(),
#       # hosts_file="hosts.txt",       # extra host / host:N lines
#       # yes=true,                     # skip confirm prompts (API default)
#       # quiet=false,
#       # verbosity=nothing,            # :quiet | :progress | :verbose
#       # sync=false,                   # or :sync / :rsync (rsync: empty remote only)
#       # collect_merge=false,          # merge into existing collect tree
#       # output_dir=nothing,           # also used as collect root when set
#       # enable_log=true,
#       # log_dir=nothing,
#       # package=nothing,              # package name hint on workers
#       # skip_hash_check=nothing,      # false → require remote git parity
#       # gb_per_worker=nothing,        # size! when a host has no :N
#       # size_probe=nothing,           # warm-up script for size! peak RSS
#       # mem_headroom=0.75,
#       # master_gb=0.4,
#   )

report_pipeline_errors(result) || exit(1)
println("pipeline! ok  (driver=", basename(driver), ")")
