# News

User-facing changes.
GitHub Releases may copy these sections (`Release notes:` on
`@JuliaRegistrator register`).

## Unreleased

### Breaking (Unreleased)

- `demo install` copies into `./distsshkit_demos/` (or
  `DIR/distsshkit_demos/` with `--dest DIR`), not `./demos/`. Package
  sources stay `demos/with_kit/` and `demos/without_kit/`.

### Other

- `setup --prune` removes `.distsshkit/{go,drive,setup}` leaves on the
  job project and remotes (`--older-than DAYS`, `--id TOKEN` for go
  batches). Does not wipe the deploy (`--delete`) or kill workers
  (`--cleanup`).
- `go` Time `collect` is the remote-pull phase: every slot script finishes
  first, then pulls. Nested `NAME/collect` no longer sits under `run`.

## 0.5.0

Breaking cut after `0.4.3`.

### Breaking (0.5.0)

- Explicit `parent[:N]` / `child:NAME[:N]` are the `drive` success contract:
  they must join, stay through the run, and collect before `ok=true` /
  exit 0. `--require-all-hosts` is the default; `--best-effort` (and
  `DISTSSHKIT_BEST_EFFORT`) restores the 0.4.3 partial-run exit 0.
  `go` already fails the batch when a listed slot does not run.
  A child that returns fewer workers than requested is not joined.
  Detached `require_all_hosts` must be a `Bool`.

### Other

- A `~/…` collect root is expanded on the host even if that directory does
  not exist yet (including names with spaces).
- Docs pages use the kit mark as the browser tab icon (`favicon.ico`).
- `go` writes the same Julia / project log header as `drive`. Time lists
  `ready` / `sync` / `run` / `collect` even on a parent-only run (`run` is the
  script, not the drive driver).
- README and Requirements: DistSSHQueue can line jobs up on a machine that stays
  on. `tmux` can still keep a job that is already running.

## 0.4.3

Patch after `0.4.2`.

- Missing `ssh` / `rsync` / `git` / `scp` on `PATH` prints a Requirements hint
  instead of a raw `ENOENT`. `setup --check` lists the three on the controller
  (`ssh` fails the check; `rsync` / `git` warn).

- Drive post-run collect and collect-missing treat SSH / `find` errors as a host
  failure (`HostRunResult.ok` is false), not an empty success. Default drive
  exit stays 0 unless `--require-all-hosts`. `go` ignores a local `go.exitcode`
  when `scp` of that file failed (a stale `0` must not look like success).

- Remote `uname` no longer assumes Linux when the probe fails. `git status`
  failure on a work tree is dirty. Project `Pkg.activate` errors surface.

## 0.4.2

- `go` with `sync=:rsync` / `:sync` checks remotes **after** the copy. Default
  `sync=false` still checks first. After `:rsync`, hosts missing Manifest deps
  get `instantiate!` (same for `drive --rsync`). Detached `execute!(; remote=)`
  that starts with `~` is left as a remote-shell layout (not `expanduser` on
  the controller).

- Testenv Docker / Apple SSH boxes are Compose/container `child-1` / `child-2`
  (peer DNS `dev@child-1`), matching Kit `child:NAME`. Image tags stay
  `linux-ssh-worker`. Controller aliases stay `distsshkit-w1` / `distsshkit-w2`.

## 0.4.1

- `go` with `job_id` / `DISTSSHKIT_JOB_ID` runs the slot script. The pkill
  mark is a no-op `-L` file so the script stays `PROGRAM_FILE`. Drive workers
  still use a comment-only `--eval=#distsshkit-job:<id>`.

## 0.4.0

Breaking cut after `0.3.3`.

### Breaking (0.4.0)

- go / drive / size placement tokens are `parent[:N]` (Kit) and
  `child:NAME[:N]` (SSH). `parenthost` is gone. `local` / `localhost` / `l`
  are ordinary SSH names (`child:local`). `--local` / `-l` raise
  `ArgumentError`. setup and collect-only still take a bare SSH name.
  `-w` fills omitted `:N`. `kit.result` stores resolved `tokens`.
- Omitted go / drive dirs sit next to the script:
  `{script}/.distsshkit/go/<stem>_<UTC>/` (slots + `kit.progress`) and
  `{script}/.distsshkit/drive` (unless `--output-dir` / `init_output_dir!`).
  Script outside the project → `{project}/.distsshkit/go/…`. Setup logs stay
  `{project}/.distsshkit/setup/`. `allocate_output_dir` uses the same
  `{script}/.distsshkit/<kind>/` tree.
- Public names match those tokens: [`is_parent_host_name`](@ref),
  `parent_gb` / `--parent-gb` / `DEFAULT_PARENT_GB`,
  [`WorkerPlan`](@ref) `parent_workers` / `child_workers`,
  `include_parent` / `include_parent_for_size`,
  [`child_hosts_from_tokens`](@ref), [`show_drive_usage`](@ref).
  `size_worker_count` takes `is_parent`. `--master-gb` raises
  `ArgumentError`. Filesystem [`canonical_local_path`](@ref),
  `execute!(…; remote=)` (project path on the SSH host),
  [`HostResult`](@ref) vs [`HostRunResult`](@ref), and
  `cleanup_remote_workers` are unchanged.

### Also in this cut

- CLI `setup` / [`setup!`](@ref) print the same Time table as go / drive
  (`kind=setup` in `kit.progress`). `sync!` / `instantiate!` from drive / go
  do not start a second progress run. Defaults for `DISTSSHKIT_JOBS` and
  `DISTRIBUTED_INIT_DELAY_SEC` are unchanged.
- `progress:` lines end with `t=<unix>` and append `kit.progress` next to
  `kit.pid` (so `--no-log` still has lines). Non-quiet drive / go print the
  Time table and a `progress DIR` replay line.
  `julia -m DistSSHKit progress DIR` reprints the last run.
- Detached `execute!` writes `kit.result` (TOML) on a normal finish;
  [`kit_result_from_dir`](@ref) / `wait` read it. Drive collect is `hosts`
  there ([`HostRunResult`](@ref); error strings as-is). `go` leaves `hosts`
  empty. `kit.pid` stores a start key; [`kit_pid_file_running`](@ref) needs
  the pid and the key. [`terminate!`](@ref) / [`terminate_run!`](@ref) then
  `pkill` only `job_id`-tagged processes. `wait(kp; timeout=N)` returns
  `failed_step="hung"` / `exit_code=124` without killing.
  Child stdio defaults to `kit.out` / `kit.err`. Sidecars
  (`kit.pid`, `kit.job`, `kit.hosts`, `kit.result`, `.kit.lock`) stay in
  `output_dir`.
- [`drive_host_status`](@ref) reads live membership from `kit.hosts.status`.
  Drive takes the output-dir lock after `init_output_dir!`.
- Drive / size RAM preflight share `mem_headroom` / `parent_gb` / CPU
  reserve (`MEMORY_CAPACITY_FRACTION` is gone). Missing remote `nproc`
  skips the CPU cap instead of inventing a huge core count.
- [`run_on_host`](@ref) detect-and-execs remote Julia in one SSH connection
  (`ignorestatus`; POSIX-quoted argv). Default [`ssh_opts`](@ref) includes
  `-o RequestTTY=no`; `request_tty=true` / `tty=true` omit it.
- [`setup!`](@ref) rejects a bad mode or `:clone` without `repo=` before
  opening the setup log. Ambient `:progress` / `:quiet` is kept so
  `Pkg.test` does not print `Log file:`. `go!` `quiet=true` still
  suppresses that banner.
- Root / `demos/` / SSH E2E `.gitignore` ignore `.distsshkit/` anywhere.
  `setup --rsync` always excludes `.distsshkit/` and `.git/`.
- Demo drivers take `--n N` (a bare `4` looked like a parent token).
- Dark-theme Documenter / README footers use `logo-dark.svg` and
  `#gh-light-mode-only` / `#gh-dark-mode-only`.
- [`host_tokens`](@ref) takes `kind=:go` or `:drive`. CLI `go` uses the same
  mapping as detached [`execute!`](@ref). [`parse_go_args`](@ref) /
  [`parse_drive_args`](@ref), SSH resolve, path helpers, and help chrome
  stay exported; `go` / `drive` argv wrappers stay unexported.

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

## 0.3.2

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

## 0.3.1

- `go!(…; output_dir=PATH)` sets the batch root (same keyword as `drive!`).
  `collect_spec::String` remains a compat alias; both set is an error.
  `collect_spec=false` still skips collect. CLI `--output-dir` is unchanged.
- Docs: LICENSE carves out Julia dots (CC BY-NC-SA 4.0, Stefan Karpinski)
  from the MIT source license. READMEs, Introduction, and
  `docs/src/assets/README.md` credit
  [julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics).
- Docs: Japanese README (`README.ja.md`). English README and Introduction
  restructured around terms, `go` / `drive`, setup, and rsync vs git.
  Topology diagram is a hand-edited SVG
  (`docs/src/assets/diagram/topology.svg`);
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

## 0.3.0

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

## 0.2.1

Patch after the first General registration (`0.2.0`).

- Library / `go!` / `drive!`: Julia **1.10+**. Terminal
  `julia -m DistSSHKit`: **1.12+**.
- `setup!` (same modes as CLI `setup`). `size!` (alias of `size_plan`).
- `go` / `drive` / `setup` / `size` share `--hosts` and `DISTSSHKIT_HOSTS`.
- Failures that need a next command: diagnose, then explain for CLI vs API.
- `drive` collect works with remote `~` roots.
- Controllers: macOS, Linux, and WSL2 Ubuntu (not native Windows).

## 0.2.0

First release on General.
