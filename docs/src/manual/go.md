# [go](@id Manual-go)

Run a **standalone** script as-is (no Kit APIs in the job file). Each
`local:N` / `host:N` slot is one full script run — not Distributed workers.

```bash
julia --project=. -m DistSSHKit go [options] [local:N] [host:N...] SCRIPT.jl [script_args...]
```

Also: [First Steps · Demo](@ref Tutorial-Demo), [drive](@ref Manual-drive),
`go --help`. Flag vocabulary: [User Guide](@ref Manual).

## Flags

| Flag | Meaning |
| --- | --- |
| `--sync` | Git push/pull before remote slots (**opt-in**; default is none) |
| `--rsync` | Rsync working tree first (empty/missing remote, or after `setup --delete`) |
| `--skip-sync` | Compat: no pre-run sync (already the default) |
| `--skip-git-guard` | Alias of `--skip-sync` (shared name with drive) |
| `--julia PATH` | Julia on remotes (default: auto / `JULIA_DISTRIBUTED_EXE`) |
| `--output-dir PATH` | **Batch root**; slots write under `PATH/<slot>/` (not `drive --output-dir`) |
| `--hosts CSV` | Comma-separated slot specs (same form as CLI tokens / `DISTSSHKIT_HOSTS`) |
| `-q` / `--quiet` | Hide terminal detail; `go_*.log` and per-slot logs still written |
| `--progress` | Thin phase bar (not with `-q`) |
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
<project>/.distsshkit/go/<stem>_<UTC>/<slot>/
```

`--output-dir PATH` replaces the **batch root**. Kit sets
`DISTRIBUTED_OUTPUT_DIR` to each slot directory.

Collect after remote slots: **slot-overwrite** (rsync whole slot dir).

## Hosts

CLI tokens, `--hosts-file`, and/or `DISTSSHKIT_HOSTS`. `local:0` skips local
slots when remotes are listed.
