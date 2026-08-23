#!/usr/bin/env julia
# DistSSHKit API demo: run pi_file.jl through `go!`
# (as-is complete job slots — the without_kit counterpart of pipeline_square.jl).
#
# Local (this script):
#
#   julia --project=. demos/without_kit/pipeline_pi.jl
#   julia --project=. demos/without_kit/pipeline_pi.jl --n 5000
#
# Same job via CLI:
#
#   julia --project=. -m DistSSHKit go parenthost:2 demos/without_kit/pi_file.jl --n 5000

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

script = joinpath(@__DIR__, "pi_file.jl")
n = string(_demo_n(ARGS; default=1000))

# Local-only: two concurrent full-job slots on this machine (not Distributed workers).
result = go!(script, "parenthost:2"; args=["--n", n])

# First-time remotes: setup!, then go!.
#
#   session = KitSession(
#       workers=["user@host1", "user@host2"],
#       remote="/path/to/project",
#       yes=true,
#   )
#   setup!(session, :rsync, :instantiate)
#   # or: setup!(session, :clone; repo="https://…"); setup!(session, :instantiate)
#   result = go!(
#       script,
#       "user@host1:1",
#       "user@host2:1";
#       remote="/path/to/project",
#       args=["--n", n],
#       # julia=nothing,                  # or path / "auto" (same as CLI --julia)
#   )
#
# Other `go!` keywords (uncomment / edit as needed):
#
#   result = go!(
#       script,
#       "user@host1:1",
#       "user@host2:1";   # or go!(script, ["user@host1:1", "user@host2:1"]; …)
#       remote="/path/to/project",
#       args=["--n", n],
#       # project=pwd(),
#       # hosts_file="hosts.txt",       # extra host / host:N lines
#       # yes=true,                     # skip confirm prompts (API default)
#       # quiet=false,
#       # verbosity=nothing,            # :quiet | :progress | :verbose
#       # sync=false,                   # or :sync / :rsync (rsync: empty remote only)
#       # output_dir=nothing,           # batch root (PATH/<slot>/); same name as drive!
#       # collect_spec=nothing,         # false → skip pull; path is a compat alias for output_dir
#       # path_anchor=nothing,          # shorten displayed paths
#   )

report_go_errors(result) || exit(1)
println("pipeline ok  (go! script=", basename(script), ")")
