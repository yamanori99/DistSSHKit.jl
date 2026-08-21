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
remote order in one call. Worker placement uses the same tokens as the CLI
(`masterhost:2`, `user@host:1`):

```julia
pipeline!(driver, "masterhost:2"; args=["8"])
pipeline!(driver, "user@h1:1", "user@h2:1"; remote="/path/to/project", args=["8"])
go!("job.jl", "masterhost:2"; args=["8"])
drive!("job.jl", "masterhost:2"; args=["8"])
```

## Run a script as-is — `go!`

No Kit imports in the job file. Each `masterhost:N` / `host:N` slot is one full run, concurrent.

```@docs
go!
GoResult
report_go_errors
KitRunResult
kit_run_result
report_run_errors
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
setup!(session, :runtest)  # optional: job Pkg.test() on remotes
# git trees: setup!(session, :clone; repo="https://…") instead of :rsync
```

[`setup!`](@ref) mirrors `julia -m DistSSHKit setup --…` (`:delete`, `:rsync`,
`:clone`, `:sync`, `:pull`, `:instantiate`, `:check`, `:runtest`, `:cleanup`).
Confirmations follow `session.yes`. **`:clone` requires `repo=`** — no silent
`origin` lookup; clone runs on the remote. [`sync!`](@ref) / [`instantiate!`](@ref)
remain as short aliases for the common deploy steps.

A few points that carry over from the CLI:

- [`go!`](@ref) / [`drive!`](@ref) / [`pipeline!`](@ref) do **not** pre-run
  sync or require git parity by default. Pass `sync=:sync` / `:rsync` for a
  one-shot deploy
- Git parity (`skip_hash_check=false`, CLI: `drive --require-git`) is
  **drive** / **pipeline** only — `go!` stays simpler
- Prefer positional worker tokens over building a [`WorkerPlan`](@ref) by
  hand (`WorkerPlan` is the return type of [`size!`](@ref))
- Pass `julia=` on `go!` / `drive!` / `pipeline!` to pin the remote Julia
  binary (same as CLI `--julia`)

Or call [`pipeline!`](@ref) for optional sync → [`size!`](@ref) → [`drive!`](@ref)
→ collect in one shot (`pipeline!` does not call [`setup!`](@ref)).
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
WorkerPlan
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

## Worker tokens — `masterhost:N` / `host:N`

Use this surface when callers need to classify tokens or decide whether
`size!` is needed before building workers (e.g. the queue layer's own
occupancy math), instead of re-parsing the grammar or reaching into
private internals.

`parse_worker_tokens` validates and classifies the grammar.
`worker_tokens_fully_specified` says whether every token has an explicit `:N`.
`remote_hosts_from_tokens` extracts only SSH host names.
`worker_plan_from_tokens` resolves to a concrete [`WorkerPlan`](@ref).
`split_worker_token` and `is_local_host_name` are the low-level primitives.

```@docs
parse_worker_tokens
ParsedWorkerTokens
worker_tokens_fully_specified
remote_hosts_from_tokens
worker_plan_from_tokens
split_worker_token
is_local_host_name
```

## One seam over `go!` / `drive!` — `execute!`

For callers that pick the kind at runtime (the queue layer): one function,
one result type, instead of branching on `kind` yourself.

```julia
execute!(:go, "job.jl", ["masterhost:2"]; args=["8"])
execute!(:drive, "job.jl", ["masterhost:2"]; args=["8"])
wait(execute!(:go, "job.jl", ["masterhost:1"]; detached=true, args=["8"]))
```

`detached=true`:

- Spawns a child `julia -m DistSSHKit go|drive` (not in-process `go!` /
  `drive!`)
- Keywords are an allow-list; `yes` must stay `true`
- Child stdio inherits the parent — `redirect_stdout` in the caller does not
  apply to the subprocess. Pass `stdout` / `stderr` to capture it instead
- [`KitProcess`](@ref) holds the `Base.Process` and the dirs resolved before
  spawn
- `wait` converts it to [`KitRunResult`](@ref); on a non-zero child exit,
  `failed_step` is `"go"` / `"drive"` only

### Progress lines (external watchers)

When a kit log file is open (`go_*.log` / `drive_*.log`), `go` and `drive`
append `progress:` lines. The last event (`done`) is written **regardless of
verbosity**. `begin` / `step` / `item` lines appear only in `--progress`
mode (`DISTSSHKIT_PROGRESS=1` for a child process).

Each line is space-separated `key=value` fields after the event name:

```text
progress: begin kind=<go|drive> label=<label> total=<steps>
progress: step kind=<go|drive> label=<label> done=<done> total=<steps> cur=<cur>
progress: item kind=<go|drive> label=<item_label> status=<pending|running|ok|fail> done=<done> total=<steps>
progress: done kind=<go|drive> ok=<true|false> done=<done> total=<steps>
```

`kind` is `go` or `drive` for those commands. Fields are not quoted; labels
are kit-chosen (phase names or slot labels) and do not contain spaces.

Queue-style watchers can set `DISTSSHKIT_PROGRESS=1` on `execute!(…;
detached=true)` children, tail the kit log, and treat `progress: done` as
the structured finish line. Slot-level `go` artifacts (`go_manifest.txt`,
`{slot}/go.exitcode`) remain the source of truth for per-slot exit codes.

```@docs
execute!
KitProcess
```

## Inside a driver — `worker_pmap`

World-age escape hatch when a driver needs `pmap`-like fan-out after defining
methods in the same session.

```@docs
worker_pmap
```
