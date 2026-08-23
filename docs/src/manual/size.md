# [size](@id Manual-size)

Estimate worker counts from host memory and CPU.

```bash
julia --project=. -m DistSSHKit size [options] [parenthost] [hosts...]
```

Also: [drive](@ref Manual-drive), `size --help`.
Flag vocabulary: [User Guide](@ref Manual).

## Flags

| Flag | Meaning |
| --- | --- |
| `parenthost` | Include this job's DistSSHKit parent (same token as `go` / `drive`; `:N` stripped) |
| `--gb-per-worker N` | Assume N GB per worker instead of measuring RSS |
| `--probe PATH` | After package load, `include` this script on each probe worker and record peak RSS |
| `--mem-headroom N` | Fraction of RAM usable for workers (default `0.75`) |
| `--master-gb N` | GB to reserve for the master process (default `0.4`) |
| `-q` / `--quiet` | Hide terminal detail during measurement |
| `--progress` | Live status (TTY default) |
| `--verbose` | Full detail (non-TTY default) |
| `-y` / `--yes` | Reserved (no prompts today; accepted for shared peel) |
| `--hosts CSV` | Comma-separated SSH hosts (`host:N` → host name only) |
| `--hosts-file PATH` | Append SSH hosts (`host:N` → host name only) |
| `-v` / `--version` | Print DistSSHKit version and exit |
| `-h` / `--help` | Full help |

Drive preflight uses the same RAM fraction as `--mem-headroom` (`pipeline!` /
`drive!(; mem_headroom=)`). CLI `drive` has no `--mem-headroom`; it uses the
default `0.75`. RSS safety / floor / fallback stay unexported constants (not
flags).

Remote project paths use the same resolution as [`drive`](@ref Manual-drive)
(`DISTRIBUTED_REMOTE_PROJECT_ROOT` / setup remote root).

Measurement is a **hint**, not a job peak: baseline is package-load RSS; with
`--probe`, peak is after that script runs. Worker counts use
`max(baseline, peak)`. Prefer an explicit `host:N` (CLI / API tokens) or
`--gb-per-worker` when you know the workload. Prefer [`size!`](@ref).
It returns a [`WorkerPlan`](@ref) for
`drive!(session, …; plan=…)`; day-to-day runs usually use tokens instead
(`drive!("job.jl", "parenthost:2"; …)`).

`DISTSSHKIT_JOBS` (default 1) parallelizes Julia-path detection only; probe
workers are still added one host at a time.

```bash
julia --project=. -m DistSSHKit size parenthost host1 host2
julia --project=. -m DistSSHKit size --probe warmup.jl parenthost
```

`warmup.jl` is ordinary Julia (top-level statements). Example:

```julia
# Allocate something representative of one worker's working set.
const _ = zeros(Float64, 10_000_000)
```
