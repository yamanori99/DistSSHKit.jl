# [size](@id Manual-size)

Estimate worker counts from host memory and CPU.

```bash
julia --project=. -m DistSSHKit size [options] [parent] [child:NAME...]
```

Also: [drive](@ref Manual-drive), `size --help`.
Flag vocabulary: [User Guide](@ref Manual).

## Flags

- `parent`: include this job's DistSSHKit parent (same token as `go` /
  `drive`; `:N` stripped)
- `--gb-per-worker N`: assume N GB per worker instead of measuring RSS
- `--probe PATH`: after package load, `include` this script on each probe
  worker and record peak RSS
- `--mem-headroom N`: fraction of RAM usable for workers (default `0.75`)
- `--parent-gb N`: GB to reserve for the parent process (default `0.4`)
- `-q` / `--quiet`: hide terminal detail during measurement
- `--progress`: live status (TTY default)
- `--verbose`: full detail (non-TTY default)
- `-y` / `--yes`: reserved (no prompts today; kept so shared CLI flags
  peel the same as go / drive / setup)
- `--hosts CSV`: comma-separated SSH hosts (`child:NAME:N` → host name
  only)
- `--hosts-file PATH`: append SSH hosts (`child:NAME:N` → host name only)
- `-v` / `--version`: print DistSSHKit version and exit
- `-h` / `--help`: full help

The CPU term is the OS core count (`hw.ncpu` on macOS, `nproc` on Linux),
not Julia's `Sys.CPU_THREADS` or `--threads=auto`. Parent hosts reserve 2
cores, children reserve 1. The formula does not change with the Julia
minor. Kit sizes **process** counts; it does not set worker thread pools.
On Apple Silicon with Julia ≤1.12, `Sys.CPU_THREADS` may look smaller
(performance-core heuristic) while Kit still uses all OS cores; Julia 1.13+
counts all cores too
([JuliaLang/julia#62891](https://github.com/JuliaLang/julia/pull/62891)).

Drive preflight uses the same RAM fraction, `parent_gb`, and CPU reserve as
`size_worker_count` (`pipeline!` / `drive!` / CLI `drive --mem-headroom`).
RSS safety / floor / fallback stay unexported constants (not flags).

Remote project paths use the same resolution as [`drive`](@ref Manual-drive)
(`DISTRIBUTED_REMOTE_PROJECT_ROOT` / setup remote root).

Measurement is a **hint**, not a job peak: baseline is package-load RSS; with
`--probe`, peak is after that script runs. Worker counts use
`max(baseline, peak)`. Prefer an explicit `child:NAME:N` (CLI / API tokens) or
`--gb-per-worker` when you know the workload. Prefer [`size!`](@ref).
It returns a [`WorkerPlan`](@ref) for
`drive!(session, …; plan=…)`; day-to-day runs usually use tokens instead
(`drive!("job.jl", "parent:2"; …)`).

`DISTSSHKIT_JOBS` (default 1) parallelizes Julia-path detection only; probe
workers are still added one host at a time.

```bash
julia --project=. -m DistSSHKit size parent host1 host2
julia --project=. -m DistSSHKit size --probe warmup.jl parent
```

`warmup.jl` is ordinary Julia (top-level statements). Example:

```julia
# Allocate something representative of one worker's working set.
const _ = zeros(Float64, 10_000_000)
```
