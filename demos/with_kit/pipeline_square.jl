#!/usr/bin/env julia
# DistSSHKit API demo: run square_file.jl through `pipeline!`
# (the usual sync → workers → drive → collect flow) instead of the `drive` CLI.
#
# Local (this script):
#
#   julia --project=. demos/with_kit/pipeline_square.jl
#   julia --project=. demos/with_kit/pipeline_square.jl 4
#
# Same driver via CLI:
#
#   julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl

using DistSSHKit

driver = joinpath(@__DIR__, "square_file.jl")
n = length(ARGS) >= 1 ? ARGS[1] : "8"

# Local-only: two Distributed workers on this machine (collect off — outputs stay local).
result = pipeline!(driver, "local:2"; args=[n], collect=false, enable_log=false)

# First-time remotes: sync + instantiate, then pipeline! (or drive!).
#
#   session = KitSession(
#       workers=["user@host1", "user@host2"],
#       remote="/path/to/project",
#   )
#   sync!(session; mode=:rsync)
#   instantiate!(session)                 # or instantiate!(session; julia="/path/to/julia")
#   result = pipeline!(
#       driver,
#       "user@host1:1",
#       "user@host2:1";
#       remote="/path/to/project",
#       args=[n],
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
#       args=[n],
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
#       # gb_per_worker=nothing,        # size_plan when a host has no :N
#       # size_probe=nothing,           # warm-up script for size_plan peak RSS
#       # mem_headroom=0.75,
#       # master_gb=0.4,
#   )

report_pipeline_errors(result) || exit(1)
println("pipeline! ok  (driver=", basename(driver), ")")
