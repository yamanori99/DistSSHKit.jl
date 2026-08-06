# [API](@id API)

```@meta
CurrentModule = DistSSHKit
```

Julia entry points when you embed DistSSHKit in a notebook or your own package.
Day-to-day work stays on the CLI (`julia --project=. -m DistSSHKit …`); see
[Introduction](@ref DistSSHKit.jl),
[First Steps](@ref Tutorial-Prepare), and the [User Guide](@ref Manual).
REPL help also works
(`?DistSSHKit.go!`).

The shape mirrors the CLI: **`go!`** for as-is scripts, **`drive!`** (and friends)
for Distributed drivers. **`pipeline!`** is optional sugar that runs the usual
remote order in one call.

## Run a script as-is — `go!`

No Kit imports in the job file. Each `local:N` / `host:N` slot is one full run.

```@docs
go!
GoResult
report_go_errors
```

## Drive work across workers

When the script is a **driver** (`init_output_dir!` / `main`, `pmap`, …), build a
[`KitSession`](@ref), then call the steps you need:

```text
(optional sync!)  →  size_plan  →  drive!  →  (optional collect!)
```

[`go!`](@ref) / [`drive!`](@ref) / [`pipeline!`](@ref) do **not** pre-run sync or
require git parity by default (same as CLI). Pass `sync=:sync` / `:rsync`, or
`skip_hash_check=false` on `drive!` / `PipelineConfig` (CLI: `--require-git`),
when you want those.

Or call [`pipeline!`](@ref) for that same order in one shot.
[`pipeline_config_from_env`](@ref) reads `DISTSSHKIT_HOSTS` /
`DISTSSHKIT_HOSTS_FILE`, `SYNC_MODE` (`rsync` / `sync` / `off`; unset → off for
remotes too), and the usual quiet / progress / yes flags — same vocabulary as
the CLI.

```@docs
KitSession
sync!
HostResult
SyncResult
size_plan
WorkerPlan
WorkerMemorySample
measure_rss
effective_worker_gb
per_worker_gb_dict
compute_worker_plan
drive!
DriveResult
collect!
CollectResult
```

```@docs
pipeline!
PipelineConfig
pipeline_config_from_env
PipelineResult
report_pipeline_errors
```

## Inside a driver — `worker_pmap`

World-age escape hatch when a driver needs `pmap`-like fan-out after defining
methods in the same session.

```@docs
worker_pmap
```

## Same argv as the CLI

[`go`](@ref) / [`drive`](@ref) accept the same argument vector as
`julia -m DistSSHKit go|drive …`. Prefer `go!` / `drive!` / `pipeline!` in new
code; these exist for thin wrappers and tests.

```@docs
go
drive
```
