# [size](@id Manual-size)

Estimate worker counts from host memory and CPU.

```bash
julia --project=. -m DistSSHKit size [options] [--local] [hosts...]
```

Also: [drive](@ref Manual-drive), `size --help`.
Flag vocabulary: [User Guide](@ref Manual).

## Flags

| Flag | Meaning |
| --- | --- |
| `-l` / `--local` | Include localhost in measurements (**boolean**; not `drive --local N`) |
| `--gb-per-worker N` | Assume N GB per worker instead of measuring RSS |
| `--probe PATH` | After package load, `include` this script on each probe worker and record peak RSS |
| `--mem-headroom N` | Fraction of RAM usable for workers (default `0.75`) |
| `--master-gb N` | GB to reserve for the master process (default `0.4`) |
| `-q` / `--quiet` | Hide terminal detail during measurement |
| `--progress` | Thin phase bar (not with `-q`) |
| `-y` / `--yes` | Reserved (no prompts today; accepted for shared peel) |
| `--hosts-file PATH` | Append SSH hosts (`host:N` → host name only) |
| `-v` / `--version` | Print DistSSHKit version and exit |
| `-h` / `--help` | Full help |

Remote project paths use the same resolution as [`drive`](@ref Manual-drive)
(`DISTRIBUTED_REMOTE_PROJECT_ROOT` / setup remote root).

Measurement is a **hint**, not a job peak: baseline is package-load RSS; with
`--probe`, peak is after that script runs. Worker counts use
`max(baseline, peak)`. Prefer an explicit `WorkerPlan` or `--gb-per-worker` when
you know the workload.

```bash
julia --project=. -m DistSSHKit size --local host1 host2
julia --project=. -m DistSSHKit size --probe warmup.jl --local
```

`warmup.jl` is ordinary Julia (top-level statements). Example:

```julia
# Allocate something representative of one worker's working set.
const _ = zeros(Float64, 10_000_000)
```
