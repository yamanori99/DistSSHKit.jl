# [User Guide](@id Manual)

Command reference. For a hands-on path, use
[First Steps](@ref Tutorial-Prepare) (Requirements → Prepare → Demo).

Full flag lists: `julia --project=. -m DistSSHKit {cmd} --help`.
Each command page starts with **Flags** for that command.

- [setup](@ref Manual-setup): check hosts, clone / rsync / sync,
  instantiate, prune, cleanup
- [go](@ref Manual-go): standalone script as-is; one full run per slot
  (`--repeat N` = N runs, spread across listed hosts)
- [drive](@ref Manual-drive): master + Distributed workers; driver farms
  work
- [size](@ref Manual-size): estimate worker counts from RAM / CPU
- [demo](@ref Manual-demo): install or list bundled example scripts
- [distsshkit](@ref Manual-distsshkit): optional terminal command
  (`pkg> app add`; experimental)

## go vs drive (pick one)

Both share host tokens (`parent:N`, `child:NAME:N`) and optional `--sync` /
`--rsync`. The difference is **what the script is**:

- **Script:** go is ordinary `.jl` (no Kit APIs). Drive is a driver with
  `init_output_dir!` / `main`.
- **`child:NAME:N`:** go is N **concurrent full script runs**. Drive is N
  **Distributed workers**.
- **Collect:** go is slot-overwrite after remotes. Drive is post-run-new
  after `main()`; optional collect-only flags.
- **Success:** go requires every listed slot to run (`ok=false` if one
  does not). Drive requires listed `parent` / `child` to join, stay, and
  collect (**default**). `--best-effort` allows a partial run.
- **Git parity:** go has no `--require-git`. Drive has opt-in
  `--require-git`.
- **`--output-dir`:** go is batch root (`PATH/{slot}/`). Drive is result
  root (`DISTRIBUTED_OUTPUT_DIR`).

If you want “run this job on a few machines,” start with **go**.
If you want one master farming work with `pmap` (and friends), use **drive**.

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
- `--hosts`: CSV tokens. `setup` strips `:N` from bare SSH names. `size`
  strips `:N` from `parent` / `child:NAME[:N]`. `go` / `drive` keep
  `child:NAME:N`.
- `--hosts-file`: same as `--hosts` for that command.
- Shared flags: `-q`/`--quiet`, `--progress`, `--verbose`, `-y`/`--yes`,
  `--hosts`, `--hosts-file`, `-v`/`--version` — same on setup / go /
  drive / size.

## Shared concepts

**Hosts.** Sources, in the order they append after positional tokens:

- CLI tokens on go / drive / size: `parent[:N]`, `child:NAME[:N]`
- CLI tokens on setup and drive collect-only: SSH name with no prefix
- `--hosts` (CSV)
- `DISTSSHKIT_HOSTS` (comma-separated)
- `--hosts-file` (default path from `DISTSSHKIT_HOSTS_FILE`)

`setup` / `size` strip `:N` and use host names only.

**Jobs.** `DISTSSHKIT_JOBS` (default 1) is the max concurrent SSH host jobs
for `setup --rsync`, drive post-run collect, and `size` Julia detection.
Worker `addprocs` stays sequential.

**Quiet / progress.**

- Default: `--progress` (live status) on a TTY; full detail when piped or
  `NO_COLOR`
- `-q` hides terminal detail; `--verbose` forces full detail — at most one
  (`DISTSSHKIT_QUIET` / `DISTSSHKIT_PROGRESS` / `DISTSSHKIT_VERBOSE`)
- Kit / slot logs still write regardless; fatals stay on the terminal
- Confirm prompts always print (`-y` / `DISTSSHKIT_YES` skips them)

**Stale workers.**

- Local `drive` workers are torn down with `rmprocs`, not a pattern `pkill`
- Before adding SSH workers, `drive` may `pkill -9 -f` `julia --worker` /
  `julia --bind-to` on those remotes
- `setup --prune` removes `.distsshkit/{go,drive,setup}` leaves (not the
  deploy). `--cleanup` kills stale workers. `--delete` removes the remote
  project tree
- `setup --cleanup` runs that same sweep on localhost and remotes (other
  Distributed jobs on the same login can match)
- `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1` skips those `pkill`s; `rmprocs`
  still runs for the current drive
- Detached `execute!(…; job_id=)` is a different contract: `pkill` only
  argv containing `distsshkit-job:<id>` ([`terminate!`](@ref)). Go slots
  `-L` a no-op file of that name so the script still runs; drive workers
  get `--eval=#distsshkit-job:<id>`

**Kit files.** Setup logs: `{project}/.distsshkit/setup/`. Go:
`{script}/.distsshkit/go/{stem}_{UTC}/`. Drive (no `--output-dir`):
`{script}/.distsshkit/drive`. Add `.distsshkit/` to the **job** project's
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
