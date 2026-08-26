# [User Guide](@id Manual)

Command reference. For a hands-on path, use
[First Steps](@ref Tutorial-Prepare) (Requirements → Prepare → Demo).

Full flag lists: `julia --project=. -m DistSSHKit {cmd} --help`.
Each command page starts with a **Flags** table for that command.

| | |
| --- | --- |
| [setup](@ref Manual-setup) | Check hosts, clone / rsync / sync, instantiate, cleanup |
| [go](@ref Manual-go) | Standalone script as-is; one full run per slot |
| [drive](@ref Manual-drive) | Master + Distributed workers; driver farms work |
| [size](@ref Manual-size) | Estimate worker counts from RAM / CPU |
| [demo](@ref Manual-demo) | Install or list bundled example scripts |
| [distsshkit](@ref Manual-distsshkit) | Optional terminal command (`pkg> app add`; experimental) |

## go vs drive (pick one)

Both share host tokens (`parent:N`, `child:NAME:N`) and optional `--sync` / `--rsync`.
The difference is **what the script is**:

| | [go](@ref Manual-go) | [drive](@ref Manual-drive) |
| --- | --- | --- |
| Script | Ordinary `.jl` (no Kit APIs) | Driver with `init_output_dir!` / `main` |
| `child:NAME:N` means | N **concurrent full script runs** | N **Distributed workers** |
| Collect | Slot-overwrite after remotes | Post-run-new after `main()`; optional collect-only flags |
| Git parity | No `--require-git` | Opt-in `--require-git` |
| `--output-dir` | Batch root (`PATH/{slot}/`) | Result root (`DISTRIBUTED_OUTPUT_DIR`) |

If you want “run this job on a few machines,” start with **go**.
If you want one master farming work with `pmap` (and friends), use **drive**.

## Flag consistency (read once)

Same **names** are shared on purpose; a few meanings differ by command:

| Topic | Rule |
| --- | --- |
| `--sync` / `--rsync` | Same git vs rsync idea on `setup` (mode) and `go` / `drive` (optional pre-run). On each command, pick at most one. `go` / `drive --rsync` instantiates if deps are missing. |
| Default pre-run sync | **`go`** and **`drive`**: **none** (run `setup` yourself, or pass `--sync` / `--rsync`). |
| Git parity (drive) | **Off** by default. Opt-in: `--require-git`. Compat: `--skip-git-guard` (no-op; may combine with `--sync` / `--rsync`). |
| Skip pre-run (go) | Compat: `--skip-sync` / `--skip-git-guard` (already the default; exclusive with `--sync` / `--rsync` on go). |
| `--output-dir` | **`go`**: batch root (`PATH/{slot}/`). **`drive`**: result root (`DISTRIBUTED_OUTPUT_DIR`). Different on purpose. |
| `--hosts` | CSV tokens. `setup` strips `:N` from bare SSH names. `size` strips `:N` from `parent` / `child:NAME[:N]`. `go` / `drive` keep `child:NAME:N`. |
| `--hosts-file` | Same as `--hosts` for that command. |
| Shared peel | `-q`/`--quiet`, `--progress`, `--verbose`, `-y`/`--yes`, `--hosts`, `--hosts-file`, `-v`/`--version` — same on setup / go / drive / size. |

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
