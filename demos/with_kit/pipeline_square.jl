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
#   julia --project=. -m DistSSHKit drive parent:2 demos/with_kit/square_file.jl --n 4

using DistSSHKit

isempty(ARGS) || (length(ARGS) == 2 && ARGS[1] == "--n") ||
    error("pass --n N (a bare number looks like parent:N)")

driver = joinpath(@__DIR__, "square_file.jl")

# Local-only: two Distributed workers on this machine (collect off — outputs stay local).
result = pipeline!(driver, "parent:2"; args=ARGS, collect=false, enable_log=false)

# First-time remotes: setup!, then pipeline! (or drive!).
#
#   session = KitSession(
#       workers=["child:user@host1", "child:user@host2"],
#       remote="/path/to/project",
#       yes=true,
#   )
#   setup!(session, :rsync, :instantiate)
#   # or: setup!(session, :clone; repo="https://…"); setup!(session, :instantiate)
#   result = pipeline!(
#       driver,
#       "child:user@host1:1",
#       "child:user@host2:1";
#       remote="/path/to/project",
#       args=ARGS,
#       # julia=nothing,                  # or path / "auto" (same as CLI --julia)
#   )
#
# Other `pipeline!` keywords (uncomment / edit as needed):
#
#   result = pipeline!(
#       driver,
#       "child:user@host1:1",
#       "child:user@host2:1";   # or pipeline!(driver, ["child:user@host1:1", …]; …)
#       remote="/path/to/project",
#       args=ARGS,
#       collect=true,                   # false → skip; path → collect root
#       # project=pwd(),
#       # hosts_file="hosts.txt",       # extra parent / child:NAME[:N] lines
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
