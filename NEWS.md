# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- `run_on_host(host, argv; julia, detect, tty)` detect-and-execs remote Julia
  in one SSH connection (same candidates as `detect_julia_path`). Does not
  replace `resolve_remote_julia`. Detect results are not persisted across
  processes.
- `host_tokens` takes `kind=:go` or `kind=:drive` (and vector methods) instead
  of guessing from `parsed.hosts isa Tuple`. `go!` writes `kit.result` at
  each `GoResult` return (no `Ref` in `finally`).
- `drive_host_status` reads live per-host membership from `kit.hosts.status`
  during `drive` (`:joined` / `:alive` / `:left` / `:collect_pending`).
  `Distributed.workers()` is the liveness probe. Post-run collect stays on
  `DriveResult.hosts`, not in `kit.result`.
- Detached sidecar files in `output_dir` (`kit.pid`, `kit.job`, `kit.hosts`,
  `kit.result`, `kit.out` / `kit.err`, `.kit.lock`) are documented as the
  on-disk contract (copies under `log_dir` when that path is distinct).
- `allocate_output_dir(kind, script; project, job_id)` creates a unique
  directory under `.distsshkit/<kind>/` for a later detached
  `output_dir=`. Optional `job_id` is appended (same charset as `execute!`).
- `wait(kp; timeout=N)` returns `failed_step="hung"` / `exit_code=124` if
  the child is still running; it does not kill. Use `terminate!` for teardown.
- `parse_progress_line` / `kit_progress_latest` read `progress:` kit log
  lines (`job_id` filter on the latter). `DISTSSHKIT_PROGRESS` is still
  only `--progress` verbosity.
- Detached `execute!` writes child stdio to `kit.out` / `kit.err` in
  `output_dir` unless `stdout` / `stderr` are passed (`stdout=stdout`
  inherits the parent).
- Exported queue CLI surface: `parse_go_args` / `parse_drive_args`, SSH
  resolve, path helpers, and help chrome (`print_colored` is the public
  name for `_print_colored`). `go` / `drive` argv wrappers stay unexported.
- `terminate!` / `terminate_run!` cancel a detached run: SIGTERM, then
  grace, then SIGKILL, then `pkill` only processes tagged with that
  `job_id` (never machine-wide `julia.*--worker`). Pass `job_id` to reap
  workers after a lost handle.
- `execute_detached_accepts` reports whether a keyword is allowed on
  detached `execute!` (`:go` / `:drive`), including named parameters.
  `kit_pid_alive` is the pid probe used for `.kit.lock` / leftover `kit.pid`.
- Detached `go` / `drive` write `kit.result` (TOML) next to `kit.pid` on a
  normal finish. `kit_result_from_dir` reads it; `wait` prefers it when present.
  A crash / SIGKILL leaves no file. Per-host collect is not in this file.
- `host_tokens(parsed)` rebuilds CLI tokens from `parse_go_args` /
  `parse_drive_args` for `execute!`. Bare hosts stay bare; drive
  `local_workers > 0` becomes `parenthost:N`.
- Detached `kit.pid` is removed when the child finishes (`go` / `drive`
  `finally`, and `wait` as backup). A leftover after SIGKILL can still look
  alive if the OS reuses the pid.

## 0.3.3

- Host token `parenthost` is this job's DistSSHKit parent (same machine when you
  start the kit yourself). Replaces the unreleased `masterhost` name (Master is
  the process; `parenthost` is the machine). `local` / `localhost` / `l` and
  `--local` / `-l` still work but warn once; they go away in **0.4**. Prefer
  `parenthost` / `parenthost:N` (no `--parenthost` flag). `size` takes the same
  token (`size parenthost host1`). Empty `go` host lists default to one parent
  slot whose directory is `parenthost` (was `local`). `drive_host_specs` emits
  `parenthost:N`. The `size` table labels that host `parenthost` too.
- `drive` worker heartbeat: leave if the master sends no pong for
  `DISTRIBUTED_HEARTBEAT_DEADLINE_SEC` (default 600, same order as SSH
  `ServerAlive`). Interval is `DISTRIBUTED_HEARTBEAT_INTERVAL_SEC` (default 30).
  A blocked ping no longer stalls the watchdog.
- `execute!(...; detached=true)` drops a best-effort `kit.pid` file (child OS
  pid) in `output_dir` (and `log_dir` if distinct), for liveness checks after
  a caller restart loses its `KitProcess`.
- `DriveResult.hosts::Vector{HostRunResult}` reports per-host collect outcome
  instead of one aggregate `ok`.
- `go!` / `drive!` (and `execute!`) write a `.kit.lock` in `output_dir` and
  fail fast (`ArgumentError`) on a second concurrent run against the same
  directory; a lock left by a dead pid is reclaimed automatically.
- `kit_progress_begin!` accepts `job_id` (or `ENV["DISTSSHKIT_JOB_ID"]`, also
  forwarded by `execute!(...; detached=true, job_id=...)`) to add `job=<id>`
  on `progress:` log lines.
- `go` / `drive` progress log lines use a stable `kind=` / `done=` / `total=`
  format (`begin` / `step` / `item` / `done`); the final `done` line is
  always written to the kit log regardless of verbosity.
- Docs: remote Julia auto-detect paths in `requirements.md` (juliaup first,
  then usual OS locations; `setup --check` / `--julia` /
  `JULIA_DISTRIBUTED_EXE`).

## 0.3.2 (2026-08-20)

- `drive` no longer `pkill`s local `julia --worker` processes before
  `addprocs`. Local teardown is `rmprocs`, run at the end of every `drive!` /
  `execute!(:drive)` call, so repeated calls in the same process leave no
  workers behind. Pre-run `pkill` remains for SSH hosts (skip with
  `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1`); machine-wide local kill stays
  `setup --cleanup`.
- Shared `KitRunResult` (`ok`, `kind`, `output_dir`, `log_dir`, `failed_step`,
  `exit_code`) plus `kit_run_result` / `report_run_errors`. `DriveResult` and
  `PipelineResult` now carry `output_dir` / `failed_step` (and
  `PipelineResult.exit_code`); `DriveResult(ok, code)` still works.
  `output_dir` / `log_dir` reflect the directory `drive` actually used, not
  just an explicitly-passed keyword.
- `execute!(kind, script, tokens; …)::KitRunResult`, `kind ∈ (:go, :drive)`:
  one seam over `go!` / `drive!` for callers that pick the kind at runtime.
  `detached=true` spawns `julia -m DistSSHKit go|drive` and returns a
  `KitProcess`; `wait(kp)` yields the same `KitRunResult`.
- Public worker-token API for `local:N` / `host:N`: `parse_worker_tokens`,
  `ParsedWorkerTokens`, `worker_tokens_fully_specified`,
  `remote_hosts_from_tokens`, `worker_plan_from_tokens`, plus primitives
  `split_worker_token` / `is_local_host_name`.
- `drive` atexit and `size!` / `measure_rss` skip `rmprocs` when only the
  driver remains, instead of warning `process 1 not removed`. `measure_rss`
  now `rmprocs`es only its own probe pids (not the whole cluster), always in
  `finally`.

## 0.3.1 (2026-08-18)

- `go!(…; output_dir=PATH)` sets the batch root (same keyword as `drive!`).
  `collect_spec::String` remains a compat alias; both set is an error.
  `collect_spec=false` still skips collect. CLI `--output-dir` is unchanged.
- Docs: LICENSE carves out Julia dots (CC BY-NC-SA 4.0, Stefan Karpinski)
  from the MIT source license. READMEs, Introduction, and
  `docs/src/assets/README.md` credit
  [julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics).
- Docs: Japanese README (`README.ja.md`). English README and Introduction
  restructured around terms, `go` / `drive`, setup, and rsync vs git.
  Topology diagram is a hand-edited SVG (`docs/src/assets/diagram/topology.svg`);
  bake writes Japanese and dark variants, plus PNG (`bake.jl --png`).
  DocumenterMermaid is gone. READMEs note that `drive` / `size` stay on
  `julia -m DistSSHKit` under the `distsshkit` app.
- Docs: `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL`, and gitignore `.distsshkit/` in
  the job project.
- `setup --sync` / `--pull` (and `go` / `drive` `--sync`, `sync!`,
  `setup!(…, :sync|:pull)`): confirm before git push/pull, same as clone.
  `-y` / `session.yes` skips the prompt.
- Opt-in `drive --require-all-hosts` / `DISTSSHKIT_REQUIRE_ALL_HOSTS` (and
  `drive!(…; require_all_hosts=true)`): fail if a listed SSH host did not join
  or post-run collect reported an error. Default remains best-effort exit 0.
- `DISTSSHKIT_JOBS` (default 1): concurrent rsync hosts, concurrent post-run
  collect hosts, and parallel `detect_julia_path` before sequential `size!`
  `addprocs`. `addprocs` itself stays sequential.

## 0.3.0 (2026-08-16)

Breaking cut after `0.2.1`. No `0.2.2` on General.

- **Breaking:** Julia **1.12+** only (library and CLI). 1.10 / 1.11 dropped.
- **Breaking:** exported `size_plan` removed; use `size!`.
- **Breaking:** `go` / `drive` argv wrappers are no longer exported. Use
  `go!` / `drive!` or `julia -m DistSSHKit`.

- Optional `pkg> app add DistSSHKit` (Pkg Apps, experimental): `distsshkit` on
  PATH. Same argv as `-m`. Prefer for `go` / `setup` / `demo`; `drive` / `size`
  stay `julia --project=. -m DistSSHKit`.

- `setup --runtest`: `Pkg.test()` of the **job** project on remotes (after
  `--check`; not DistSSHKit's own `Pkg.test()`).

- **Breaking:** `demo install` copies one family (`with_kit` or `without_kit`),
  not both. Bare `demo install` refuses. API: `install_demos(; family=...)`.

- Confirm prompts always print (`-q` / `--progress` included). `-y` still skips
  them.

- CLI job root: `julia -m DistSSHKit` from a project that depends on DistSSHKit
  uses that project's `Project.toml`, not the kit's.
  `DISTRIBUTED_PROJECT_ROOT` overrides.

## 0.2.1 (2026-08-14)

Patch after the first General registration (`0.2.0`).

- Library / `go!` / `drive!`: Julia **1.10+**. Terminal `julia -m DistSSHKit`: **1.12+**.
- `setup!` (same modes as CLI `setup`). `size!` (alias of `size_plan`).
- `go` / `drive` / `setup` / `size` share `--hosts` and `DISTSSHKIT_HOSTS`.
- Failures that need a next command: diagnose, then explain for CLI vs API.
- `drive` collect works with remote `~` roots.
- Controllers: macOS, Linux, and WSL2 Ubuntu (not native Windows).

## 0.2.0 (2026-08-11)

First release on General.
