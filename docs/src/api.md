# [API](@id API)

```@meta
CurrentModule = DistSSHKit
```

Julia entry points when you embed DistSSHKit in a notebook or your own package.
Day-to-day work stays on the CLI (`julia --project=. -m DistSSHKit …`, Julia
**1.12+** preferred); see
[Introduction](@ref DistSSHKit.jl),
[First Steps](@ref Tutorial-Prepare), and the [User Guide](@ref Manual).
On 1.10–1.11 use the functions here, or `DistSSHKit.main` as in
[Requirements](@ref).
REPL help also works
(`?DistSSHKit.go!`).

The shape mirrors the CLI: **`go!`** for as-is scripts, **`drive!`** (and friends)
for Distributed drivers. **`pipeline!`** is optional sugar that runs the usual
remote order in one call. Worker placement uses the same tokens as the CLI
(`local:2`, `user@host:1`):

```julia
pipeline!(driver, "local:2"; args=["8"])
pipeline!(driver, "user@h1:1", "user@h2:1"; remote="/path/to/project", args=["8"])
go!("job.jl", "local:2"; args=["8"])
drive!("job.jl", "local:2"; args=["8"])
```

## Run a script as-is — `go!`

No Kit imports in the job file. Each `local:N` / `host:N` slot is one full run, concurrent.

```@docs
go!
GoResult
report_go_errors
```

## Drive work across workers

When the script is a **driver** (`init_output_dir!` / `main`, `pmap`, …), build a
[`KitSession`](@ref), then call the steps you need:

```text
(optional setup! / sync! / instantiate!)  →  size!  →  drive!  →  (optional collect!)
```

First-time remotes usually look like:

```julia
session = KitSession(workers=["user@h1"], remote="/path/to/project", yes=true)
setup!(session, :delete, :rsync, :instantiate)
setup!(session, :check; ignore_julia_version=true)  # optional
# git trees: setup!(session, :clone; repo="https://…") instead of :rsync
```

[`setup!`](@ref) mirrors `julia -m DistSSHKit setup --…` (`:delete`, `:rsync`,
`:clone`, `:sync`, `:pull`, `:instantiate`, `:check`, `:cleanup`). Confirmations
follow `session.yes`. **`:clone` requires `repo=`** (no silent `origin` lookup;
clone runs on the remote). [`sync!`](@ref) / [`instantiate!`](@ref) remain as
short aliases for the common deploy steps.

[`go!`](@ref) / [`drive!`](@ref) / [`pipeline!`](@ref) do **not** pre-run sync or
require git parity by default (same as CLI). Pass `sync=:sync` / `:rsync` when
you want a one-shot deploy. Git parity (`skip_hash_check=false`, CLI:
`drive --require-git`) is **drive** / **pipeline** only — `go!` stays simpler.
Prefer positional worker tokens over building a [`WorkerPlan`](@ref) by hand
(`WorkerPlan` remains the return type of [`size!`](@ref) / [`size_plan`](@ref)).
Pass `julia=` on `go!` / `drive!` / `pipeline!` to pin the remote Julia binary
(same as CLI `--julia`).

Or call [`pipeline!`](@ref) for that same order in one shot.
[`pipeline_config_from_env`](@ref) reads `DISTSSHKIT_HOSTS` /
`DISTSSHKIT_HOSTS_FILE`, `SYNC_MODE` (`rsync` / `sync` / `off`; unset → off for
remotes too), `JULIA_DISTRIBUTED_EXE` (same as CLI `--julia`), and the usual
quiet / progress / yes flags — same vocabulary as the CLI.

```@docs
KitSession
setup!
sync!
instantiate!
HostResult
SyncResult
size!
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
