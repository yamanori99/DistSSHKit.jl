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

The shape mirrors the CLI: **`go!`** for as-is scripts, **`drive!`**
(and friends) for Distributed drivers. **`pipeline!`** is optional sugar
that runs the usual remote order in one call. Worker placement uses the
same tokens as the CLI (`parent:2`, `child:user@host:1`):

```julia
pipeline!(driver, "parent:2"; args=["8"])
pipeline!(
    driver, "child:user@h1:1", "child:user@h2:1";
    remote="/path/to/project", args=["8"],
)
go!("job.jl", "parent:2"; args=["8"])
drive!("job.jl", "parent:2"; args=["8"])
```

## Run a script as-is — `go!`

No Kit imports in the job file. Each `parent:N` / `child:NAME:N` slot is
one full run, concurrent. `repeat=N` is N runs in total (`--repeat N`),
spread across listed hosts.

```@docs
go!
GoResult
report_go_errors
KitRunResult
kit_run_result
report_run_errors
```

## Drive work across workers

When the script is a **driver** (`init_output_dir!` / `main`, `pmap`,
…), build a [`KitSession`](@ref), then call the steps you need:

```text
(optional setup! / sync! / instantiate!)
  →  size!  →  drive!  →  (optional collect!)
```

First-time remotes usually look like:

```julia
session = KitSession(
    workers=["child:user@h1"], remote="/path/to/project", yes=true,
)
setup!(session, :delete, :rsync, :instantiate)
setup!(session, :check; ignore_julia_version=true)  # optional
setup!(session, :runtest)  # optional: job Pkg.test() on remotes
# git trees: setup!(session, :clone; repo="https://…") instead of :rsync
```

[`setup!`](@ref) mirrors `julia -m DistSSHKit setup --…` (`:delete`, `:rsync`,
`:clone`, `:sync`, `:pull`, `:instantiate`, `:check`, `:runtest`, `:cleanup`).
Confirmations follow `session.yes`. **`:clone` requires `repo=`** — no silent
`origin` lookup; clone runs on the remote.
[`sync!`](@ref) / [`instantiate!`](@ref)
remain as short aliases for the common deploy steps.

A few points that carry over from the CLI:

- [`go!`](@ref) / [`drive!`](@ref) do **not** pre-run sync or require git
  parity by default. Pass `sync=:sync` / `:rsync` to copy first; after
  `:rsync`, missing Manifest deps get [`instantiate!`](@ref).
  [`pipeline!`](@ref) may `sync!` first but does not pass `sync=` into
  `drive!`, so it does not instantiate after rsync
- Git parity (`skip_hash_check=false`, CLI: `drive --require-git`) is
  **drive** / **pipeline** only — `go!` stays simpler
- Listed `drive` placements must join, stay, and collect
  (`require_all_hosts=true`, the default). Pass `require_all_hosts=false`
  for a 0.4.3-style partial run
- Prefer positional worker tokens over building a [`WorkerPlan`](@ref) by
  hand (`WorkerPlan` is the return type of [`size!`](@ref))
- Pass `julia=` on `go!` / `drive!` / `pipeline!` to pin the remote Julia
  binary (same as CLI `--julia`)

Or call [`pipeline!`](@ref) for optional sync → [`size!`](@ref) →
[`drive!`](@ref)
→ collect in one shot (`pipeline!` does not call [`setup!`](@ref)).
[`pipeline_config_from_env`](@ref) reads `DISTSSHKIT_HOSTS` /
`DISTSSHKIT_HOSTS_FILE`, `SYNC_MODE` (`rsync` / `sync` / `off`; unset → off for
remotes too), `JULIA_DISTRIBUTED_EXE` (same as CLI `--julia`), and the usual
quiet / progress / yes flags — same vocabulary as the CLI.

`DriveResult.hosts` is one [`HostRunResult`](@ref) per host that joined as a
worker (empty when no host-collection step ran). The same vector is in
`kit.result` for a detached caller that only has `output_dir`.
[`HostResult`](@ref) is the per-host row for setup / sync, not drive collect.

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

## Worker tokens — `parent:N` / `child:NAME:N`

Use this surface when callers need to classify tokens or decide whether
`size!` is needed before building workers (occupancy math), instead of
re-parsing the grammar or reaching into private internals.

`parse_worker_tokens` validates and classifies the grammar.
`worker_tokens_fully_specified` says whether every token has an explicit `:N`.
`child_hosts_from_tokens` extracts only SSH host names.
`worker_plan_from_tokens` resolves to a concrete [`WorkerPlan`](@ref).
`split_worker_token` and `is_parent_host_name` are the low-level primitives
(`is_parent_host_name` is `parent` only).
`host_tokens(parsed; kind=:go|:drive)` rebuilds `execute!` token strings from
`parse_go_args` / `parse_drive_args`. Go keeps parser strings; drive emits
`parent:N` from `parent_workers` and `child:NAME[:N]` for SSH.

```@docs
parse_worker_tokens
ParsedWorkerTokens
worker_tokens_fully_specified
child_hosts_from_tokens
worker_plan_from_tokens
split_worker_token
is_parent_host_name
host_tokens
```

## One seam over `go!` / `drive!` — `execute!`

For callers that pick the kind at runtime: one function,
one result type, instead of branching on `kind` yourself.

```julia
execute!(:go, "job.jl", ["parent:2"]; args=["8"])
execute!(:drive, "job.jl", ["parent:2"]; args=["8"])
wait(execute!(:go, "job.jl", ["parent:1"]; detached=true, args=["8"]))
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
  exit yields `failed_step` `"go"` / `"drive"` only. `wait(kp; timeout=N)`
  returns `failed_step="hung"` / `exit_code=124` without killing the child

```@docs
execute!
allocate_output_dir
execute_detached_accepts
execute_kwargs_from_parsed
KitProcess
kit_pid_alive
kit_pid_file_running
terminate!
terminate_run!
kit_result_from_dir
drive_host_status
DriveHostStatus
```

### Progress lines (external watchers)

When a kit log file is open (`go_*.log` / `drive_*.log`), `go` and `drive`
append `progress:` lines. The same lines go to `kit.progress` in `output_dir`
(even with `--no-log`). The last event (`done`) is written **regardless of
verbosity**. `begin` / `step` / `item` lines appear only in `--progress`
mode (`DISTSSHKIT_PROGRESS=1` for a child process).

Each line is space-separated `key=value` fields after the event name.
`t=` is Unix time (seconds) at the end of every line. Events:

- `begin`: `kind`, optional `job`, `label`, `total`, `t`
- `step`: `kind`, optional `job`, `label`, `done`, `total`, `cur`, `t`
- `item`: `kind`, optional `job`, `label` (item), `status`
  (`pending` / `running` / `ok` / `fail`), `done`, `total`, `t`
- `done`: `kind`, optional `job`, `ok`, `done`, `total`, `t`

`kind` is `go` or `drive`. `job=` is present only when `job_id` /
`DISTSSHKIT_JOB_ID` is set. Fields are not quoted; labels are kit-chosen
(phase names or slot labels) and do not contain spaces.

Watchers can tail `kit.progress` (or the kit log) and use
[`parse_progress_line`](@ref) / [`kit_progress_latest`](@ref) /
[`kit_progress_phases`](@ref), or `julia -m DistSSHKit progress DIR`.
`DISTSSHKIT_PROGRESS=1` is `--progress` verbosity on the child, not a watcher.
Slot-level `go` artifacts (`go_manifest.txt`, `{slot}/go.exitcode`) remain
the source of truth for per-slot exit codes.

```@docs
parse_progress_line
kit_progress_latest
kit_progress_phases
```

### Helpers for detached runs

Opt-in extras on `go!` / `drive!` (in-process or detached) for a caller
that runs many jobs.

#### Still holding `KitProcess`

[`terminate!`](@ref) SIGTERMs the child, waits `grace` for its `rmprocs`
path, then SIGKILLs if needed, then `pkill`s only argv tagged with this
run's `job_id`. `kp.process` is still a `Base.Process` if you need `kill`
yourself.

#### Sidecar files (`output_dir`)

On-disk contract for a detached (or in-process) run. `kit.pid`, `kit.job`,
`kit.hosts`, `kit.hosts.status`, and `kit.result` are also written under
`log_dir` when that path is distinct. `.kit.lock` and `kit.out` / `kit.err`
stay in `output_dir`. Kit logs (`go_*.log` / `drive_*.log`) are not this list.

- `.kit.lock`: pid of the process holding the dir. A second run against
  the same path raises `ArgumentError`. A lock left by a dead pid is
  reclaimed.
- `kit.pid`: child OS pid, optional start key on the second line.
  Running is [`kit_pid_file_running`](@ref) (pid plus start).
  [`kit_pid_alive`](@ref) is the pid-only probe. Removed on a normal
  finish. A leftover is SIGKILL / crash.
- `kit.job`: `job_id` when set. [`terminate_run!`](@ref) uses it for
  tagged `pkill` after a restart.
- `kit.hosts`: remote hosts this run started (one name per line), written
  after workers join. `terminate_run!` reaps these.
- `kit.hosts.status`: live per-host membership during `drive` (`:joined` /
  `:alive` / `:left` / `:collect_pending`). Read with
  [`drive_host_status`](@ref). Not the post-run collect vector.
- `kit.result`: TOML with the same fields as [`KitRunResult`](@ref),
  including `hosts` (post-run collect, [`HostRunResult`](@ref) rows).
  Omitted when empty (`go`, or a `drive` that never collected). Read with
  [`kit_result_from_dir`](@ref). Missing while running or after a hard
  death.
- `kit.progress`: `progress:` lines for watchers
  (`kit_progress_latest`). Written even when `--no-log` skips
  `drive_*.log`.
- `kit.out` / `kit.err`: detached child stdio when `stdout` / `stderr`
  were omitted.

Together: running (`kit.pid` live and start matches, no result), finished
(result present), or died hard (leftover pid that is dead or reused, no
result).

#### Handle gone

[`terminate_run!`](@ref) reads `kit.pid` / `kit.job` / `kit.hosts` and uses
the same signal-then-tagged-`pkill` sequence as [`terminate!`](@ref).
Without `job_id`, only the child pid is signaled.

#### Before spawn

- [`allocate_output_dir`](@ref): create a unique directory under
  `{script}/.distsshkit/<kind>/` for a later `output_dir=`. Omitted `go`
  default is `{script}/.distsshkit/go/<stem>_<UTC>/`; drive's omitted
  default is the shared `{script}/.distsshkit/drive`. Allocate a unique dir
  instead of sharing the drive folder.
- [`execute_kwargs_from_parsed`](@ref): map `parse_go_args` /
  `parse_drive_args` onto detached `execute!` keywords. Hosts stay in
  [`host_tokens`](@ref); `:workers` is drive `--workers` when set.
  `:log_dir` / `:mem_headroom` / `:parent_gb` / `:workers` are drive-only;
  `:plan` is never accepted.
- `job_id` (`execute!` keyword, or `ENV["DISTSSHKIT_JOB_ID"]` for in-process
  `go!` / `drive!`): `job=<id>` on every `progress:` line. Drive workers get a
  comment-only `--eval=#distsshkit-job:<id>`; go slots `-L` a no-op file of
  that name so the user script stays `PROGRAM_FILE`. [`terminate!`](@ref)
  `pkill`s that argv tag. Unset: tagging is off; teardown cannot be host-scoped.
- `.kit.lock` in the resolved `output_dir`: a second run against the same
  directory raises `ArgumentError`. A lock left by a dead pid is reclaimed.

## CLI parsers and helpers

A second package may call these. They are exported so a rename is a Semver
break, not a silent `DistSSHKit._…` change. `go` / `drive` argv wrappers stay
unexported.

```@docs
parse_go_args
parse_drive_args
show_go_usage
show_drive_usage
println_kit_version
ssh_opts
resolve_remote_julia
run_on_host
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

Default `ssh_opts()` is BatchMode and `RequestTTY=no`.
`ssh_opts(; request_tty=true)` omits `RequestTTY=no` (does not insert `-t`;
that is `ssh`-only). Setting `DISTRIBUTED_SSH_OPTS` replaces that vector;
`-F` alone does not keep `RequestTTY=no`. Use `-o RequestTTY=no`, not
`ssh -T` (`scp -T` means something else). `run_on_host(; tty=true)` still
requests a pty. Non-zero exit is `.exitcode` on the returned `Process`
(no `ProcessFailedException`).

## Inside a driver — `worker_pmap`

World-age escape hatch when a driver needs `pmap`-like fan-out after defining
methods in the same session.

```@docs
worker_pmap
```
