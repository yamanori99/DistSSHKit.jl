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
(`parenthost:2`, `user@host:1`):

```julia
pipeline!(driver, "parenthost:2"; args=["8"])
pipeline!(driver, "user@h1:1", "user@h2:1"; remote="/path/to/project", args=["8"])
go!("job.jl", "parenthost:2"; args=["8"])
drive!("job.jl", "parenthost:2"; args=["8"])
```

## Run a script as-is — `go!`

No Kit imports in the job file. Each `parenthost:N` / `host:N` slot is one full run, concurrent.

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

`DriveResult.hosts` is one [`HostRunResult`](@ref) per host that joined as a
worker (empty when no host-collection step ran) — the queue layer can use it
to tell which hosts failed without re-parsing logs.

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
HostRunResult
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

## Worker tokens — `parenthost:N` / `host:N`

Use this surface when callers need to classify tokens or decide whether
`size!` is needed before building workers (e.g. the queue layer's own
occupancy math), instead of re-parsing the grammar or reaching into
private internals.

`parse_worker_tokens` validates and classifies the grammar.
`worker_tokens_fully_specified` says whether every token has an explicit `:N`.
`remote_hosts_from_tokens` extracts only SSH host names.
`worker_plan_from_tokens` resolves to a concrete [`WorkerPlan`](@ref).
`split_worker_token` and `is_local_host_name` are the low-level primitives.
`host_tokens` rebuilds `execute!` token strings from `parse_go_args` /
`parse_drive_args` (bare hosts stay bare).

```@docs
parse_worker_tokens
ParsedWorkerTokens
worker_tokens_fully_specified
remote_hosts_from_tokens
worker_plan_from_tokens
split_worker_token
is_local_host_name
host_tokens
```

## One seam over `go!` / `drive!` — `execute!`

For callers that pick the kind at runtime (the queue layer): one function,
one result type, instead of branching on `kind` yourself.

```julia
execute!(:go, "job.jl", ["parenthost:2"]; args=["8"])
execute!(:drive, "job.jl", ["parenthost:2"]; args=["8"])
wait(execute!(:go, "job.jl", ["parenthost:1"]; detached=true, args=["8"]))
```

`detached=true`:

- Spawns a child `julia -m DistSSHKit go|drive` (not in-process `go!` /
  `drive!`)
- Keywords are an allow-list; `yes` must stay `true`
- Child stdio defaults to `kit.out` / `kit.err` in `output_dir`. Pass
  `stdout` / `stderr` to override (`stdout=stdout` inherits the parent).
  Parent `redirect_stdout` does not apply to the subprocess
- [`KitProcess`](@ref) holds the `Base.Process` and the dirs resolved before
  spawn
- `wait` converts it to [`KitRunResult`](@ref). If the child wrote `kit.result`,
  that file wins (including `go!` `failed_step`). Otherwise a non-zero child
  exit yields `failed_step` `"go"` / `"drive"` only

```@docs
execute!
execute_detached_accepts
KitProcess
kit_pid_alive
terminate!
terminate_run!
kit_result_from_dir
```

### Progress lines (external watchers)

When a kit log file is open (`go_*.log` / `drive_*.log`), `go` and `drive`
append `progress:` lines. The last event (`done`) is written **regardless of
verbosity**. `begin` / `step` / `item` lines appear only in `--progress`
mode (`DISTSSHKIT_PROGRESS=1` for a child process).

Each line is space-separated `key=value` fields after the event name:

```text
progress: begin kind=<go|drive> [job=<id>] label=<label> total=<steps>
progress: step kind=<go|drive> [job=<id>] label=<label> done=<done> total=<steps> cur=<cur>
progress: item kind=<go|drive> [job=<id>] label=<item_label> status=<pending|running|ok|fail> done=<done> total=<steps>
progress: done kind=<go|drive> [job=<id>] ok=<true|false> done=<done> total=<steps>
```

`kind` is `go` or `drive`. `job=` is present only when `job_id` /
`DISTSSHKIT_JOB_ID` is set. Fields are not quoted; labels are kit-chosen
(phase names or slot labels) and do not contain spaces.

Queue-style watchers can set `DISTSSHKIT_PROGRESS=1` on `execute!(…;
detached=true)` children, tail the kit log, and treat `progress: done` as
the structured finish line. Slot-level `go` artifacts (`go_manifest.txt`,
`{slot}/go.exitcode`) remain the source of truth for per-slot exit codes.

### Helpers for a queue layer

Opt-in extras on `go!` / `drive!` (in-process or detached) for a queue
that runs many jobs.

#### Still holding `KitProcess`

[`terminate!`](@ref) SIGTERMs the child, waits `grace` for its `rmprocs`
path, then SIGKILLs if needed, then `pkill`s only argv tagged with this
run's `job_id`. `kp.process` is still a `Base.Process` if you need `kill`
yourself.

#### Handle gone

Queue restart: files in `output_dir`, and `log_dir` if distinct.

| File | Meaning |
| --- | --- |
| `kit.pid` | Child OS pid (plain text). Probe with [`kit_pid_alive`](@ref); do not parse logs. |
| `kit.job` | `job_id` when set (needed to reap tagged workers after a restart). |
| `kit.hosts` | Remote hosts this run started (one name per line). Written after workers join. |
| `kit.result` | TOML with the same fields as [`KitRunResult`](@ref). Read with [`kit_result_from_dir`](@ref). |
| `kit.out` / `kit.err` | Detached child stdio when `stdout` / `stderr` were omitted. |

Together: running (`kit.pid` live, no result), finished (result present),
or died hard (leftover pid, no result). Per-host collect is not in
`kit.result`.

`kit.pid` is removed in the child's `finally` when it still names this pid
(same rule as `.kit.lock`); `wait` does the same as backup. After a normal
exit the file is gone. A leftover means SIGKILL / crash. A dead pid means
the job is not running; a reused pid can still look alive (starttime is
not in the file). [`kit_result_from_dir`](@ref) is `nothing` while running
or after a hard death. [`terminate_run!`](@ref) reads `kit.pid` / `kit.job` /
`kit.hosts` and uses the same signal-then-tagged-`pkill` sequence. Without
`job_id`, only the child pid is signaled.

#### Before spawn

- [`execute_detached_accepts`](@ref): whether detached `execute!` accepts
  that keyword for `:go` / `:drive` (named parameters plus the throw-path
  allow-list). `:log_dir` is drive-only; `:plan` is never accepted.
- `job_id` (`execute!` keyword, or `ENV["DISTSSHKIT_JOB_ID"]` for in-process
  `go!` / `drive!`): `job=<id>` on every `progress:` line, and a cmdline
  mark on workers / go slots so [`terminate!`](@ref) can reap only this run.
  Unset: tagging is off; teardown cannot be host-scoped.
- `.kit.lock` in the resolved `output_dir`: a second run against the same
  directory raises `ArgumentError`. A lock left by a dead pid is reclaimed.

## Queue-layer CLI surface

A second package may call these (DistSSHKitQueue does today). They are
exported so a rename is a Semver break, not a silent `DistSSHKit._…` change.
`go` / `drive` argv wrappers stay unexported.

```@docs
parse_go_args
parse_drive_args
show_go_usage
show_drive_requirements
println_kit_version
ssh_opts
resolve_remote_julia
resolve_controller_julia
canonical_local_path
short_path
resolve_pkg_project_dir
explain_script_not_found
print_cli_error
print_help_chrome
print_help_section
print_help_lines
print_help_blank
print_colored
SPINNER_FRAMES
```

`print_colored` is the public name; `_print_colored` is the same function.

## Inside a driver — `worker_pmap`

World-age escape hatch when a driver needs `pmap`-like fan-out after defining
methods in the same session.

```@docs
worker_pmap
```
