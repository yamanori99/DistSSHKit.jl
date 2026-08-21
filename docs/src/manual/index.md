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

Both share host tokens (`masterhost:N`, `host:N`) and optional `--sync` / `--rsync`.
The difference is **what the script is**:

| | [go](@ref Manual-go) | [drive](@ref Manual-drive) |
| --- | --- | --- |
| Script | Ordinary `.jl` (no Kit APIs) | Driver with `init_output_dir!` / `main` |
| `host:N` means | N **concurrent full script runs** | N **Distributed workers** |
| Collect | Slot-overwrite after remotes | Post-run-new after `main()`; optional collect-only flags |
| Git parity | No `--require-git` | Opt-in `--require-git` |
| `--output-dir` | Batch root (`PATH/{slot}/`) | Result root (`DISTRIBUTED_OUTPUT_DIR`) |

If you want “run this job on a few machines,” start with **go**.
If you want one master farming work with `pmap` (and friends), use **drive**.

## Flag consistency (read once)

Same **names** are shared on purpose; a few meanings differ by command:

| Topic | Rule |
| --- | --- |
| `--sync` / `--rsync` | Same git vs rsync idea on `setup` (mode) and `go` / `drive` (optional pre-run). On each command, pick at most one. |
| Default pre-run sync | **`go`** and **`drive`**: **none** (run `setup` yourself, or pass `--sync` / `--rsync`). |
| Git parity (drive) | **Off** by default. Opt-in: `--require-git`. Compat: `--skip-git-guard` (no-op; may combine with `--sync` / `--rsync`). |
| Skip pre-run (go) | Compat: `--skip-sync` / `--skip-git-guard` (already the default; exclusive with `--sync` / `--rsync` on go). |
| `--output-dir` | **`go`**: batch root (`PATH/{slot}/`). **`drive`**: result root (`DISTRIBUTED_OUTPUT_DIR`). Different on purpose. |
| `-l` / `--local` | Deprecated relative alias (removed in 0.4). **`drive`**: count for `masterhost:N`. **`size`**: boolean include-parent. Prefer the `masterhost` token. |
| `--hosts` | CSV tokens. `setup` / `size` strip `:N`. `go` / `drive` keep `host:N`. |
| `--hosts-file` | `setup` / `size` strip `:N`. `go` / `drive` keep `host:N` for slots / workers. |
| Shared peel | `-q`/`--quiet`, `--progress`, `--verbose`, `-y`/`--yes`, `--hosts`, `--hosts-file`, `-v`/`--version` — same on setup / go / drive / size. |

## Shared concepts

**Hosts.** Sources, in the order they append after positional tokens:

- CLI tokens (`masterhost:N`, `host:N`) on setup / go / drive / size
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

**Kit files.** Logs and go batches live under `{project}/.distsshkit/`. Add
that directory to the **job** project's `.gitignore` — DistSSHKit's own repo
already ignores it, but `Pkg.add` does not. Otherwise `go` output can show up
as untracked files, including under `drive --require-git`.

**Collect modes:**

| Mode | Where |
| --- | --- |
| **slot-overwrite** | `go` after each remote slot (whole slot dir) |
| **post-run-new** | `drive` after `main()` (newer than run-start sentinel) |
| **collect-missing** | `drive --collect-missing` / `collect!(merge=false)` |
| **collect-overwrite** | `drive --collect-overwrite` / `collect!(merge=true)` |
