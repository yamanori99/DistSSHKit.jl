#!/usr/bin/env julia
# DistSSHKit API demo: run the square_file driver through `pipeline!`
# (sync → workers → drive → collect) instead of the `drive` CLI.
#
# Local (no remotes — sync/collect stay off):
#
#   julia --project=. demos/with_kit/pipeline_square.jl
#   julia --project=. demos/with_kit/pipeline_square.jl 4
#
# Same driver via CLI:
#
#   julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
#
# With remotes (after `setup`), set hosts / sync via ENV, e.g.:
#
#   DISTSSHKIT_HOSTS=user@host1:4,user@host2:4 SYNC_MODE=rsync \
#     julia --project=. demos/with_kit/pipeline_square.jl
#
# Or build PipelineConfig yourself (`hosts=`, `sync=:rsync` / `:sync`,
# `workers=WorkerPlan(...)`). Non-empty SSH `hosts` enables pipeline collect
# into the driver `output/` directory.

using DistSSHKit

function main()
    driver = joinpath(@__DIR__, "square_file.jl")
    n = length(ARGS) >= 1 ? ARGS[1] : "8"
    has_env_hosts =
        !isempty(strip(get(ENV, "DISTSSHKIT_HOSTS", ""))) ||
        !isempty(strip(get(ENV, "DISTSSHKIT_HOSTS_FILE", "")))

    cfg = if has_env_hosts
        # DISTSSHKIT_HOSTS / SYNC_MODE / quiet flags — same vocabulary as CLI.
        c = pipeline_config_from_env(; driver=driver)
        c.script_args = [n]
        c.enable_log = false
        c.yes = true
        c
    else
        # Local-only: worker counts on WorkerPlan; empty hosts ⇒ no sync/collect.
        PipelineConfig(;
            driver=driver,
            hosts=String[],
            workers=WorkerPlan(2, Dict{String,Int}()),
            script_args=[n],
            sync=false,
            collect=false,
            enable_log=false,
            yes=true,
        )
    end

    result = pipeline!(cfg)
    report_pipeline_errors(result) || exit(1)
    println("pipeline! ok  (driver=", basename(driver), ")")
end

main()
