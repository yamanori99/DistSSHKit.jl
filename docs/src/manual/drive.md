# [drive](@id Manual-drive)

One master plus [Distributed.jl](https://docs.julialang.org/en/v1/manual/distributed-computing/)
workers. The script is a **driver** that farms work (e.g. `pmap`).

```bash
julia --project=. -m DistSSHKit drive [options] [parenthost:N] [host:N...] SCRIPT.jl [script_args...]
```

Also: [First Steps · Demo](@ref Tutorial-Demo), [go](@ref Manual-go),
[API](@ref API) (`drive!`, `pipeline!`), `drive --help`.
Flag vocabulary and a short **go vs drive** table: [User Guide](@ref Manual).

**vs go:** one master plus Distributed workers; `host:N` is worker count.
Opt-in git parity is here only (`--require-git`). For a plain script with no
driver contract, prefer [`go`](@ref Manual-go).

## Flags

| Flag | Meaning |
| --- | --- |
| `--sync` | Git push/pull immediately before the run (**optional**; default is none; confirm unless `-y`) |
| `--rsync` | Rsync deploy first (empty/missing remote, or after `setup --delete`) |
| `--require-git` | Opt-in git parity: dirty-tree warn + remote commit must match local |
| `--require-all-hosts` | Fail if a listed SSH host did not join, or if collect reported an error (default: best-effort, exit 0) |
| `--skip-git-guard` | Compat no-op (parity already off) |
| `-w` / `--workers N` | Default worker count for hosts without `:N` (also `-w:N`) |
| `-l` / `--local N` | Deprecated alias of `parenthost:N` (relative; removed in 0.4; **count**, not size) |
| `--julia PATH` | Julia on SSH workers |
| `--output-dir PATH` | **Result root** → `DISTRIBUTED_OUTPUT_DIR` (not go batch root) |
| `--log-dir PATH` | Log directory override |
| `--no-log` | Do not write `drive_<timestamp>.log` |
| `--package NAME` | `using NAME` on workers (override Project.toml name) |
| `--collect-missing ROOT HOST...` | Collect-only: remote files absent locally |
| `--collect-overwrite ROOT HOST...` | Collect-only: merge remote tree (overwrite same names) |
| `-q` / `--quiet` | Hide terminal detail; kit log still written when logging is on |
| `--progress` | Live status (TTY default) |
| `--verbose` | Full detail (non-TTY default) |
| `-y` / `--yes` | Auto-accept memory-pressure and other prompts |
| `--hosts CSV` | Comma-separated worker specs (same form as CLI tokens / `DISTSSHKIT_HOSTS`) |
| `--hosts-file PATH` | Append worker specs (`host:N` preserved) |
| `-v` / `--version` | Print DistSSHKit version and exit |
| `-h` / `--help` | Full help |

- `--sync` / `--rsync` are mutually exclusive (pre-run sync)
- `--require-git` cannot combine with `--rsync` or `--skip-git-guard`
- `--skip-git-guard` is a compat no-op (parity already off) and may combine
  with `--sync` / `--rsync`
- Default pre-run sync and git parity are both **none** (same idea as
  [`go`](@ref Manual-go)). Prepare remotes with [`setup`](@ref Manual-setup),
  or pass `--sync` / `--rsync`. Use `--require-git` only on git-managed
  remotes.

`DISTSSHKIT_REQUIRE_ALL_HOSTS=1` is the same as `--require-all-hosts`.
`DISTSSHKIT_JOBS` (default 1) caps concurrent SSH host work for rsync,
post-run collect, and `size` Julia-path detection.

## Prerequisites

Run [`setup --check`](@ref Manual-setup) on new clusters. Remotes need the
project tree and an instantiate. Prefer matching Julia **major.minor**.

## Workers

`parenthost:N` / `host:N` (or `-w` defaults). Size with [`size`](@ref Manual-size).

- Local workers are torn down with `rmprocs` at the end of every `drive` run
- Before adding SSH workers, `drive` may `pkill` leftover Distributed
  processes on those hosts; skip with `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1`
  ([User Guide](@ref Manual))
- Machine-wide local kill is `setup --cleanup`

## Results / collect

After `main()`: **post-run-new** collect. Standalone pull via the collect
flags above. See [User Guide](@ref Manual) for mode names.

External watchers: set `DISTSSHKIT_PROGRESS=1` so the kit log also gets
`progress: begin` / `step` lines; `progress: done` is always written when
logging is on (`--no-log` skips the file). Line format: [API](@ref API)
(Progress lines).

Collect expands remote `~/…` roots on each host before `find` / rsync so the
controller never `relpath`s against a tilde base (same ENV as
[setup remote path](@ref Manual-setup)).

## Driver script

Expects `init_output_dir!` / `main` (and optional hooks). Details and ENV:
`drive --help`. Embed with [`drive!`](@ref) / [`pipeline!`](@ref).

## Concurrent runs

Two `drive` runs (or `drive!` calls) against the same result root fail fast:
a `.kit.lock` file (this run's pid) is written under the result root, and a
second run against the same directory raises immediately instead of
interleaving collect output. A lock left behind by a crashed/killed run is
detected as stale (dead pid) and reclaimed automatically — no manual cleanup
needed. Use distinct `--output-dir` per concurrent job if you intend to run
more than one at a time.
