#!/usr/bin/env julia
# DistSSHKit API demo: run pi_file.jl through `go!`
# (as-is complete job slots — the without_kit counterpart of pipeline_square.jl).
#
# Local (this script):
#
#   julia --project=. distsshkit_demos/without_kit/pipeline_pi.jl
#   julia --project=. distsshkit_demos/without_kit/pipeline_pi.jl --n 5000
#
# Same job via CLI:
#
#   julia --project=. -m DistSSHKit go parent:2 distsshkit_demos/without_kit/pi_file.jl --n 5000

using DistSSHKit

isempty(ARGS) || (length(ARGS) == 2 && ARGS[1] == "--n") ||
    error("pass --n N (a bare number looks like parent:N)")

script = joinpath(@__DIR__, "pi_file.jl")

# Local-only: two concurrent full-job slots on this machine (not Distributed workers).
result = go!(script, "parent:2"; args=ARGS)

# First-time remotes: setup!, then go!.
#
#   session = KitSession(
#       workers=["child:user@host1", "child:user@host2"],
#       remote="/path/to/project",
#       yes=true,
#   )
#   setup!(session, :rsync, :instantiate)
#   # or: setup!(session, :clone; repo="https://…"); setup!(session, :instantiate)
#   result = go!(
#       script,
#       "child:user@host1:1",
#       "child:user@host2:1";
#       remote="/path/to/project",
#       args=ARGS,
#       # julia=nothing,                  # or path / "auto" (same as CLI --julia)
#   )
#
# Other `go!` keywords (uncomment / edit as needed):
#
#   result = go!(
#       script,
#       "child:user@host1:1",
#       "child:user@host2:1";   # or go!(script, ["child:user@host1:1", "child:user@host2:1"]; …)
#       remote="/path/to/project",
#       args=ARGS,
#       # project=pwd(),
#       # hosts_file="hosts.txt",       # extra parent / child:NAME[:N] lines
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
