# [drive](@id Manual-drive)

One master plus
[Distributed.jl](https://docs.julialang.org/en/v1/manual/distributed-computing/)
workers. The script is a **driver** that farms work (e.g. `pmap`).

```bash
julia --project=. -m DistSSHKit drive [options] \
  [parent:N] [child:NAME[:N]...] SCRIPT.jl [script_args...]
```

Also: [First Steps · Demo](@ref Tutorial-Demo), [go](@ref Manual-go),
[API](@ref API) (`drive!`, `pipeline!`), `drive --help`.
Flag vocabulary and a short **go vs drive** table: [User Guide](@ref Manual).

**vs go / ride:** one master plus Distributed workers; `child:NAME:N` is
worker count. Three phases: **Load** (master `include`), **Publish** (defs /
`using` / `import` / `include` on workers), **Run** (`main()` if defined).
No Distributed vocabulary in **this** file is a warning, not a refusal.
[`plan`](@ref Manual-plan) may still suggest [`go`](@ref Manual-go) or
[`ride`](@ref Manual-ride). Full-file worker `include`: `--sync-script`.
Opt-in git parity is
here only (`--require-git`). Prepare remotes with
[`setup --rsync`](@ref Manual-setup) **or** `--clone`, then `--instantiate`.
One-shot onto an empty/missing path: `drive --rsync` (instantiates if needed).

## Flags

- `--sync` / `--rsync`: optional pre-run copy; `--rsync` instantiates if needed
- `--sync-script`: re-`include` the full driver on workers (default publishes
  definitions only)
- `--require-git`: opt-in git parity: dirty-tree warn + remote commit must
  match local
- `--require-all-hosts`: fail unless every explicit `parent[:N]` /
  `child:NAME[:N]` joined, stayed, and collect succeeded (**default**)
- `--best-effort`: allow a partial run (missing join or collect error does
  not fail)
- `--skip-git-guard`: compat no-op (parity already off)
- `-w` / `--workers N`: default worker count for hosts without `:N` (also
  `-w:N`)
- `--julia PATH`: Julia on SSH workers
- `--mem-headroom N`: RAM fraction for memory preflight (default `0.75`;
  same as [`size`](@ref Manual-size))
- `--parent-gb N`: GB reserved for the parent process (default `0.4`; same
  as size)
- `--output-dir PATH`: **result root** → `DISTRIBUTED_OUTPUT_DIR` (not go
  batch root)
- `--log-dir PATH`: log directory override
- `--no-log`: do not write `drive_<timestamp>.log`
- `--package NAME`: `using NAME` on workers (override Project.toml name)
- `--collect-missing ROOT HOST...`: collect-only: remote files absent
  locally
- `--collect-overwrite ROOT HOST...`: collect-only: merge remote tree
  (overwrite same names)
- `-q` / `--quiet`: hide terminal detail; kit log still written when
  logging is on
- `--progress`: live status (TTY default)
- `--verbose`: full detail (non-TTY default)
- `-y` / `--yes`: auto-accept memory-pressure and other prompts
- `--hosts CSV`: comma-separated worker specs (same form as CLI tokens /
  `DISTSSHKIT_HOSTS`)
- `--hosts-file PATH`: append worker specs (`child:NAME:N` preserved)
- `-v` / `--version`: print DistSSHKit version and exit
- `-h` / `--help`: full help

- `--sync` / `--rsync` are mutually exclusive (pre-run sync)
- `--require-git` cannot combine with `--rsync` or `--skip-git-guard`
- `--skip-git-guard` is a compat no-op (parity already off) and may combine
  with `--sync` / `--rsync`
- Default pre-run sync and git parity are both **none** (same idea as
  [`go`](@ref Manual-go)). Prepare remotes with [`setup`](@ref Manual-setup),
  or pass `--sync` / `--rsync`. `--rsync` instantiates when the copied tree
  still lacks deps. Use `--require-git` only on git-managed remotes.

`DISTSSHKIT_REQUIRE_ALL_HOSTS=1` is the same as `--require-all-hosts`
(already the default when neither flag/env is set).
`DISTSSHKIT_BEST_EFFORT=1` is the same as `--best-effort` (cannot combine with
the require-all env).
`DISTSSHKIT_JOBS` (default 1) caps concurrent SSH host work for rsync,
post-run collect, and `size` Julia-path detection.

## Prerequisites

Run [`setup --check`](@ref Manual-setup) on new clusters. Remotes need the
project tree and an instantiate (`setup --instantiate`, or `drive --rsync`
onto an empty path). Prefer matching Julia **major.minor**; align with
[`setup --juliaup`](@ref Manual-setup) when juliaup is already on the host
([Requirements](@ref)).

## Workers

`parent:N` / `child:NAME:N` (or `-w` defaults). Size with
[`size`](@ref Manual-size).

- Local workers are torn down with `rmprocs` at the end of every `drive` run
- Before adding SSH workers, `drive` may `pkill` leftover Distributed
  processes on those hosts; skip with `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1`
  ([User Guide](@ref Manual))
- Machine-wide local kill is `setup --cleanup`

## Results / collect

After `main()`: **post-run-new** collect. Standalone pull via the collect
flags above. See [User Guide](@ref Manual) for mode names.
SSH / `find` errors on a host are a collect failure (`HostRunResult.ok` is
false), not an empty success. Default CLI exit is non-zero unless
`--best-effort`.

External watchers: `progress: begin` / `step` / `item` always go to
`kit.progress` (even `-q` / `--no-log`). The kit log still gets those lines
only with `--progress` (TTY default) or `DISTSSHKIT_PROGRESS=1`.
`progress: done` is always in both. Line format: [API](@ref API)
(Progress lines).

Collect expands remote `~/…` roots on each host before `find` / rsync so the
kit parent never `relpath`s against a tilde base (same ENV as
[setup remote path](@ref Manual-setup)).

## Driver script

Expects `init_output_dir!` / `main` (and optional hooks). Top-level work on
Load is not repeated on workers unless `--sync-script`. Details and ENV:
`drive --help`. Embed with [`drive!`](@ref) / [`pipeline!`](@ref).

## Wall time

Run drive as usual (`-q` hides the table). The Time table prints at the end,
after job stdout, with a `progress DIR` line to replay:

```bash
julia --project=. -m DistSSHKit drive -y parent:4 \
  distsshkit_demos/with_kit/square_echo.jl --n 4
julia --project=. -m DistSSHKit progress DIR
```

`DIR` is the result root (`--output-dir`, a driver's `init_output_dir!`,
or `{script}/.distsshkit/drive/<stem>_<UTC>/`).
`--progress` is the TTY default.

`progress:` lines end with `t=<unix>` ([API](@ref API)). Drive labels:
`sync` (optional), `git`, `cleanup`, `workers` (`addprocs` + Julia detect),
`wait` (SSH connection grace; `DISTRIBUTED_INIT_DELAY_SEC`, default 5; skipped
when there are no SSH hosts), `init`,
`run`, `collect`. Nested rows under each host: `workers` / `init` / `collect`
(and `cleanup` on remotes). `wait` is a fixed sleep. Leave
`DISTRIBUTED_INIT_DELAY_SEC` and `DISTSSHKIT_JOBS` (default 1) unless a
remote run gives a reason to change them.

## Concurrent runs

Two `drive` runs (or `drive!` calls) against the same result root fail fast:
a `.kit.lock` file (this run's pid) is written under the result root, and a
second run against the same directory raises immediately instead of
interleaving collect output. A lock left behind by a crashed/killed run is
detected as stale (dead pid) and reclaimed automatically — no manual cleanup
needed. Concurrent runs of the same script get distinct default dirs.
Use a shared `--output-dir` (or the same `init_output_dir!` path) only when
you intend one result root — a second run against that directory raises
until the first releases `.kit.lock`.
