# [go](@id Manual-go)

Run a **standalone** script as-is (no Kit APIs in the job file). Each
`masterhost:N` / `host:N` slot is one full script run, started **concurrently** —
not Distributed workers.

```bash
julia --project=. -m DistSSHKit go [options] [masterhost:N] [host:N...] SCRIPT.jl [script_args...]
```

Also: [First Steps · Demo](@ref Tutorial-Demo), [drive](@ref Manual-drive),
`go --help`. Flag vocabulary and a short **go vs drive** table:
[User Guide](@ref Manual).

**vs drive:** each `host:N` is N full script runs (not Distributed workers).
There is no `--require-git`; for commit parity use [`drive --require-git`](@ref Manual-drive).
Prepare remotes with [`setup --rsync`](@ref Manual-setup) **or** `--clone`, then
`--instantiate` (git updates later: `setup --sync` or `go --sync`).

## Flags

| Flag | Meaning |
| --- | --- |
| `--sync` | Git push/pull before remote slots (**opt-in**; default is none; confirm unless `-y`) |
| `--rsync` | Rsync working tree first (empty/missing remote, or after `setup --delete`) |
| `--skip-sync` | Compat: no pre-run sync (already the default) |
| `--skip-git-guard` | Alias of `--skip-sync` (shared name with drive) |
| `--julia PATH` | Julia on remotes (default: auto / `JULIA_DISTRIBUTED_EXE`) |
| `--output-dir PATH` | **Batch root**; slots write under `PATH/{slot}/` (not `drive --output-dir`) |
| `--hosts CSV` | Comma-separated slot specs (same form as CLI tokens / `DISTSSHKIT_HOSTS`) |
| `-q` / `--quiet` | Hide terminal detail; `go_*.log` and per-slot logs still written |
| `--progress` | Live status (TTY default) |
| `--verbose` | Full detail (non-TTY default) |
| `-y` / `--yes` | Non-interactive confirmations |
| `--hosts-file PATH` | Append slot specs (`host:N` preserved) |
| `-v` / `--version` | Print DistSSHKit version and exit |
| `-h` / `--help` | Full help |

`--sync` / `--rsync` / `--skip-sync` (and `--skip-git-guard`) are mutually exclusive.
Default pre-run sync is **none** (same as [`drive`](@ref Manual-drive));
prepare remotes with [`setup`](@ref Manual-setup), or pass `--sync` / `--rsync`.

## Output

Default batch root:

```text
{project}/.distsshkit/go/{stem}_{UTC}/{slot}/
```

`--output-dir PATH` replaces the **batch root**. Kit sets
`DISTRIBUTED_OUTPUT_DIR` to each slot directory.
Add `.distsshkit/` to the job project's `.gitignore` so these paths stay
untracked ([User Guide](@ref Manual)).

From the API, `go!(...; output_dir=PATH)` sets the same batch root (matching
[`drive!`](@ref Manual-drive)). `collect_spec::String` still works as a
backward-compatible alias, but passing both `output_dir` and `collect_spec::String`
is an error. `collect_spec=false` skips collect and is orthogonal to `output_dir`.

Collect after remote slots: **slot-overwrite** (rsync whole slot dir).

## Hosts

CLI tokens, `--hosts`, `--hosts-file`, and/or `DISTSSHKIT_HOSTS`. `masterhost:0` skips parent
slots when remotes are listed. Omitting hosts is one parent slot (`masterhost/`).
`local:N` is a deprecated relative alias (removed in 0.4).
