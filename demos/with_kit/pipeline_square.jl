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
#
# Remotes (after `setup`): uncomment the remote `pipeline!` block below.
# See also demos/README.md and the `pipeline!` docs.

using DistSSHKit

driver = joinpath(@__DIR__, "square_file.jl")
n = length(ARGS) >= 1 ? ARGS[1] : "8"

# Local-only: two workers on this machine. Empty `hosts` skips sync/collect
# (results are already under demos/with_kit/output/).
result = pipeline!(
    driver=driver,
    hosts=String[],
    workers=WorkerPlan(2, Dict{String,Int}()),
    script_args=[n],
    sync=false,
    collect=false,
    enable_log=false,
    yes=true,
)

# Remotes (after `setup --check YourHost…`). Uncomment and edit:
# result = pipeline!(
#     driver=driver,
#     hosts=["user@YourHost1:4", "user@YourHost2:4"],  # SSH hosts; :N = workers
#     # workers=WorkerPlan(2, Dict{String,Int}()),     # optional local workers too
#     script_args=[n],
#     sync=:rsync,   # or :sync — required onto empty remotes / after setup --delete
#     collect=true,  # pull results into demos/with_kit/output/
#     enable_log=false,
#     yes=true,
# )

report_pipeline_errors(result) || exit(1)
println("pipeline! ok  (driver=", basename(driver), ")")
