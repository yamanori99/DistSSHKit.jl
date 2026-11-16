# [User Guide](@id Manual)

Command reference. For a hands-on path, use
[First Steps](@ref Tutorial-Prepare) (Requirements → Prepare → Demo), or
start on a queue host at
[Prepare the machine](@ref Queue-Tutorial-Prepare), then
[First job](@ref Queue-Tutorial-Client).

Full flag lists: `julia --project=. -m DistSSHKit help {cmd}`.
Each command page starts with **Flags** for that command.

## How you operate it

`julia -m DistSSHKit` covers host prep ([`setup`](@ref Manual-setup), [`up`](@ref Manual-up)), runs that start on **this machine** ([`go`](@ref Manual-go), [`drive`](@ref Manual-drive), [`ride`](@ref Manual-ride)), and client verbs toward an **always-on queue host** (`submit`, `status`, `fetch`, … — [How it runs](@ref Queue-manual)).

- **This machine:** the SSH session from your laptop (or login node) stays up until the job finishes.
- **Queue host:** you leave the job on another machine; jobs run one at a time there so you can disconnect. `qhost:` names that host on client commands.

**Prepare hosts** is shared: do [`setup`](@ref Manual-setup) (and match Julia with [`up`](@ref Manual-up)) before either path.

## Prepare hosts

Shared by a job you start here and a job you leave on a queue host.

- [setup](@ref Manual-setup): check hosts, clone / rsync / sync,
  instantiate, prune, cleanup
- [up](@ref Manual-up): the same Julia channel on each machine

## This machine

Start a job here. The SSH connection stays open until it finishes.
The machine the run starts from is this machine.

- [go](@ref Manual-go): standalone script as-is; one full run per slot
  (`--repeat N` = N runs, spread across listed hosts)
- [ride](@ref Manual-ride): experimental auto-split of map / filter
  (head or SSH workers)
- [drive](@ref Manual-drive): master + Distributed workers; driver farms
  work
- [hostinfo](@ref Manual-hostinfo): host identity / RAM / CPU / Julia
- [pool](@ref Manual-pool): cluster cores / health; no job
- [paths](@ref Manual-paths): `stored_path` / content-hash cache / `push_cache!`
- [demo](@ref Manual-demo): install or list bundled example scripts

`progress` has no page of its own. `julia -m DistSSHKit progress DIR`
reprints the last phase seconds from a job you started here.

## Always-on machine

A **queue host** is an always-on machine. Leave jobs there. They run
one at a time. The machine the run starts from is the queue host.

- [How it runs](@ref Queue-manual)
- [Artifacts and paths](@ref Queue-artifacts)
- [submit](@ref Queue-submit): leave `go` / `ride` / `drive` there
- [status](@ref Queue-status)
- [fetch](@ref Queue-fetch)
- [hosts](@ref Queue-hosts)
- [serve](@ref Queue-serve)
- [setup](@ref Queue-setup)

## go vs drive (pick one)

Both share machine tokens (`N*host`, `--head-workers` / `--head-slots`) and
optional `--sync` / `--rsync`. The difference is **what the script is**:

- **Script:** go is ordinary `.jl` (the job file does not call DistSSHKit). Drive is a driver with
  `init_output_dir!` / `main`.
- **`N*host`:** go is N **concurrent full script runs**. Omit a count
  only with `--repeat` (uncapped). Drive is N **Distributed workers** on
  that host; bare host = 1 worker. Head: go uses `--head-slots`; drive /
  ride use `--head-workers` (default 0 until set). Inspect with
  [`hostinfo`](@ref Manual-hostinfo) / [`pool`](@ref Manual-pool).
- **Collect:** go is slot-overwrite after remotes. Drive is post-run-new
  after `main()`; optional collect-only flags.
- **Success:** go requires every listed slot to run (`ok=false` if one
  does not). Drive requires listed remotes and head workers to join, stay, and
  collect (**default**). `--best-effort` allows a partial run.
- **Git parity:** go has no `--require-git`. Drive has opt-in
  `--require-git`.
- **`--output-dir`:** go is batch root (`PATH/{slot}/`). Drive is result
  root (`DISTRIBUTED_OUTPUT_DIR`).

If you want “run this job on a few machines,” start with **go**.
If you want one master farming work with `pmap` (and friends), use **drive**.

**ride** is an experimental auto-split of `map` / `filter` ([`ride`](@ref Manual-ride)).

## Topology (`drive`)

```@raw html
<p style="text-align:center">
<img class="docs-light-only"
  alt="Drive topology: Master process on head, workers on head and remotes"
  src="assets/diagram/topology.svg">
<img class="docs-dark-only"
  alt="Drive topology: Master process on head, workers on head and remotes"
  src="assets/diagram/topology-dark.svg">
</p>
```

One master on the machine the run starts from, workers on each host.
**go** uses the same machine tokens, but there is no master/worker split: each host runs the script on its own.

Example placement (quote `*` in the shell):

```text
--head-workers 2       # drive / ride: two workers on this machine
--head-slots 2         # go: two slots on this machine
2*user@hostname        # two on that SSH host
user@hostname          # bare host = one worker/slot (go)
```

Each SSH host needs passwordless SSH from where you start the run and a matching Julia **major.minor** ([`setup --check`](@ref Manual-setup), [`up`](@ref Manual-up)). More: [Requirements](@ref).

## Flag consistency (read once)

Same **names** are shared on purpose; a few meanings differ by command:

- `--sync` / `--rsync`: same git vs rsync idea on `setup` (mode) and
  `go` / `drive` (optional pre-run). On each command, pick at most one.
  `go` / `drive --rsync` instantiates if deps are missing.
- Default pre-run sync: **`go`** and **`drive`**: **none** (run `setup`
  yourself, or pass `--sync` / `--rsync`).
- Git parity (drive): **off** by default. Opt-in: `--require-git`. Compat:
  `--skip-git-guard` (no-op; may combine with `--sync` / `--rsync`).
- Host reliability (drive): **on** by default (`--require-all-hosts`). Opt
  out: `--best-effort` / `DISTSSHKIT_BEST_EFFORT`.
- Skip pre-run (go): compat `--skip-sync` / `--skip-git-guard` (already the
  default; exclusive with `--sync` / `--rsync` on go).
- `--output-dir`: **`go`** is batch root (`PATH/{slot}/`). **`drive`** is
  result root (`DISTRIBUTED_OUTPUT_DIR`). Different on purpose.
- `--hosts`: CSV tokens. `setup` / `hostinfo` / `pool` strip counts from
  `N*host` and use SSH names only. `go` / `ride` / `drive` keep full
  machine tokens.
- `--hosts-file`: same as `--hosts` for that command.
- Shared flags: `-q`/`--quiet`, `--progress`, `--verbose`, `-y`/`--yes`,
  `--hosts`, `--hosts-file`, `-v`/`--version` — same on setup / go /
  drive / hostinfo / pool.

## Shared concepts

- **Host** — this machine (head) or an SSH destination (`user@hostname`, Host alias).
- **Process** — one `julia` OS process; a run may start several per host.
- **Master / worker** — `drive` topology only; **`go`** has no master/worker split.

**Hosts.** Sources, in the order they append after positional tokens:

- CLI tokens: `setup` / `hostinfo` / `pool` take SSH host names; `go` /
  `ride` / `drive` use `N*host` and `--head-workers` / `--head-slots`
- `--hosts` (CSV)
- `DISTSSHKIT_HOSTS` (comma-separated)
- `--hosts-file` (default path from `DISTSSHKIT_HOSTS_FILE`)

`setup` / `hostinfo` / `pool` strip `N*host` counts and use host names only.
On setup, `parent` is only for [`up`](@ref Manual-up); other modes take bare
SSH host names.

**Jobs.** `DISTSSHKIT_JOBS` (default 1) is the max concurrent SSH host jobs
for `setup --rsync`, drive post-run collect, and `hostinfo` Julia detection.
Worker `addprocs` stays sequential.

**Quiet / progress.**

- Default: `--progress` (live status) on a TTY; full detail when piped or
  `NO_COLOR`
- `-q` hides terminal detail; `--verbose` forces full detail — at most one
  (`DISTSSHKIT_QUIET` / `DISTSSHKIT_PROGRESS` / `DISTSSHKIT_VERBOSE`)
- Slot logs still write regardless; fatals stay on the terminal
- Confirm prompts always print (`-y` / `DISTSSHKIT_YES` skips them).
  `setup --delete`, `setup --prune`, and `teardown` ignore that skip and
  need `--confirm-path`

**Stale workers.**

- Local `drive` workers are torn down with `rmprocs`, not a pattern `pkill`
- `drive` does not `pkill -f julia --worker` on remotes. With `job_id` /
  `DISTSSHKIT_JOB_ID` it `pkill`s argv `distsshkit-job:<id>`. Skip that leftover
  pkill with `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1`; `rmprocs` still runs
- `setup --prune` removes `.distsshkit/{go,drive,setup,runs}` leaves (not the
  deploy). `--cleanup` kills stale workers (untagged `julia --worker` /
  `--bind-to` on localhost and remotes; other Distributed jobs on the same
  login can match). `--delete` removes the remote project tree
- Detached `execute!(…; job_id=)` is a different contract: `pkill` only
  argv containing `distsshkit-job:<id>` ([`terminate!`](@ref)). Go slots
  `-L` a no-op file of that name so the script still runs; drive workers
  get `--eval=#distsshkit-job:<id>`

**Files on disk.** Setup logs: `{project}/.distsshkit/setup/` (or the current
run dir when `DISTSSHKIT_RUN_DIR` is set). Artifacts: go
`{script}/.distsshkit/go/{stem}_{UTC}/`; drive (no `--output-dir` and no
`init_output_dir!`): `{script}/.distsshkit/drive/{stem}_{UTC}/`. Sidecars
(`run.toml`, pid, stdio): `{script}/.distsshkit/runs/<kind>/{stem}_{UTC}/`
(if that tree is not writable: `{project}/.distsshkit/runs/…`, then
`tempdir()/distsshkit-runs/…`). Add `.distsshkit/` to the **job** project's
`.gitignore` — DistSSHKit's own repo already ignores it, but `Pkg.add`
does not. Otherwise go/drive output can show up as untracked files,
including under `drive --require-git`.

**Collect modes:**

| Mode | Where |
| --- | --- |
| **slot-overwrite** | `go` after each remote slot (whole slot dir) |
| **post-run-new** | `drive` after `main()` (newer than run-start sentinel) |
| **collect-missing** | `drive --collect-missing` / `collect!(merge=false)` |
| **collect-overwrite** | `drive --collect-overwrite` / `collect!(merge=true)` |
