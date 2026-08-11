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
# Remotes: after you have exercised `pipeline!` on your own hosts/containers,
# copy this file and set `hosts=` / `sync=` (see demos/README.md and `pipeline!`).

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
report_pipeline_errors(result) || exit(1)
println("pipeline! ok  (driver=", basename(driver), ")")
