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

## go vs drive (pick one)

Both share host tokens (`local:N`, `host:N`) and optional `--sync` / `--rsync`.
The difference is **what the script is**:

| | [go](@ref Manual-go) | [drive](@ref Manual-drive) |
| --- | --- | --- |
| Script | Ordinary `.jl` (no Kit APIs) | Driver with `init_output_dir!` / `main` |
| `host:N` means | N **full script runs** | N **Distributed workers** |
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
| `-l` / `--local` | **`drive`**: `local:N` worker count. **`size`**: include localhost (boolean). |
| `--hosts-file` | `setup` / `size` strip `:N`. `go` / `drive` keep `host:N` for slots / workers. |
| Shared peel | `-q` / `--quiet`, `--progress`, `-y` / `--yes`, `--hosts-file`, `-v` / `--version` on setup / go / drive / size. |

## Shared concepts

**Hosts.** CLI tokens (`local:N`, `host:N`), `--hosts-file`, and/or `DISTSSHKIT_HOSTS`
(comma-separated; go / drive). `DISTSSHKIT_HOSTS_FILE` sets the default hosts-file
path. `setup` strips `:N` and uses host names only.

**Quiet / progress.** `-q` hides terminal detail; `--progress` shows a thin phase bar
instead (`DISTSSHKIT_QUIET` / `DISTSSHKIT_PROGRESS`; not together). Kit / slot logs
still write. Fatals stay on the terminal.

**Collect modes:**

| Mode | Where |
| --- | --- |
| **slot-overwrite** | `go` after each remote slot (whole slot dir) |
| **post-run-new** | `drive` after `main()` (newer than run-start sentinel) |
| **collect-missing** | `drive --collect-missing` / `collect!(merge=false)` |
| **collect-overwrite** | `drive --collect-overwrite` / `collect!(merge=true)` |
