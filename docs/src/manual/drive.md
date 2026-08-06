# [drive](@id Manual-drive)

One master plus [Distributed.jl](https://docs.julialang.org/en/v1/manual/distributed-computing/)
workers. The script is a **driver** that farms work (e.g. `pmap`).

```bash
julia --project=. -m DistSSHKit drive [options] [local:N] [host:N...] SCRIPT.jl [script_args...]
```

Also: [First Steps · Demo](@ref Tutorial-Demo), [go](@ref Manual-go),
[API](@ref API) (`drive!`, `pipeline!`), `drive --help`.
Flag vocabulary: [User Guide](@ref Manual).

## Flags

| Flag | Meaning |
| --- | --- |
| `--sync` | Git push/pull immediately before the run (**optional**; default is none) |
| `--rsync` | Rsync deploy first (empty/missing remote, or after `setup --delete`) |
| `--require-git` | Opt-in git parity: dirty-tree warn + remote commit must match local |
| `--skip-git-guard` | Compat no-op (parity already off) |
| `-w` / `--workers N` | Default worker count for hosts without `:N` (also `-w:N`) |
| `-l` / `--local N` | Alias for `local:N` (also `--local:N`; **count**, not size) |
| `--julia PATH` | Julia on SSH workers |
| `--output-dir PATH` | **Result root** → `DISTRIBUTED_OUTPUT_DIR` (not go batch root) |
| `--log-dir PATH` | Log directory override |
| `--no-log` | Do not write `drive_<timestamp>.log` |
| `--package NAME` | `using NAME` on workers (override Project.toml name) |
| `--collect-missing ROOT HOST...` | Collect-only: remote files absent locally |
| `--collect-overwrite ROOT HOST...` | Collect-only: merge remote tree (overwrite same names) |
| `-q` / `--quiet` | Hide terminal detail; kit log still written when logging is on |
| `--progress` | Thin phase bar (not with `-q`) |
| `-y` / `--yes` | Auto-accept memory-pressure and other prompts |
| `--hosts-file PATH` | Append worker specs (`host:N` preserved) |
| `-v` / `--version` | Print DistSSHKit version and exit |
| `-h` / `--help` | Full help |

`--sync` / `--rsync` are mutually exclusive (pre-run sync).
`--require-git` cannot combine with `--rsync` or `--skip-git-guard`.
`--skip-git-guard` is a compat no-op (parity already off) and may combine with
`--sync` / `--rsync`.
Default pre-run sync and git parity are both **none** (same idea as
[`go`](@ref Manual-go)). Prepare remotes with [`setup`](@ref Manual-setup),
or pass `--sync` / `--rsync`. Use `--require-git` only on git-managed remotes.

## Prerequisites

Run [`setup --check`](@ref Manual-setup) on new clusters. Remotes need the
project tree and an instantiate. Prefer matching Julia **major.minor**.

## Workers

`local:N` / `host:N` (or `-w` defaults). Size with
[`size`](@ref Manual-size).

## Results / collect

After `main()`: **post-run-new** collect. Standalone pull via the collect
flags above. See [User Guide](@ref Manual) for mode names.

## Driver script

Expects `init_output_dir!` / `main` (and optional hooks). Details and ENV:
`drive --help`. Embed with [`drive!`](@ref) / [`pipeline!`](@ref).
