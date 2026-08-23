# demos/

Install one family:

| Path | Role | Command |
| --- | --- | --- |
| [`with_kit/`](with_kit/) | Driver scripts (`init` / `main`) | `drive` or `pipeline!` |
| [`without_kit/`](without_kit/) | Standalone Julia scripts | `julia …`, `go`, or `go!` |

```text
demos/
  with_kit/
    square_file.jl      # file: square_results.csv
    square_echo.jl      # stdout only
    pipeline_square.jl  # API: pipeline!(driver, "parenthost:2")
  without_kit/
    pi_file.jl          # file: pi_results.txt
    pi_echo.jl          # stdout only
    pipeline_pi.jl      # API: go!(script, "parenthost:2") → pi_file.jl
```

Naming: `{topic}_{file|echo}` — `*_file` writes a file, `*_echo` prints only.
`pipeline_square.jl` / `pipeline_pi.jl` are thin API wrappers over the `*_file` jobs.

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo install without_kit
julia --project=. -m DistSSHKit drive parenthost:2 demos/with_kit/square_file.jl --n 4
julia --project=. -m DistSSHKit drive parenthost:2 demos/with_kit/square_echo.jl --n 4
julia --project=. demos/with_kit/pipeline_square.jl --n 4
julia demos/without_kit/pi_echo.jl --n 5000
julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl --n 5000
julia --project=. demos/without_kit/pipeline_pi.jl --n 5000
```

## with_kit/

| Script | Output |
| --- | --- |
| `square_file.jl` | `square_results.csv` |
| `square_echo.jl` | stdout |
| `pipeline_square.jl` | same CSV via `pipeline!` |

Drivers use `init_output_dir!` + `main` + `pmap`. Work count is `--n N`
(default 8), not a positional integer. Optional hooks: `drive --help`.
`pipeline_square.jl` is the thin API entry (optional sync → size! → drive! →
collect) over `square_file.jl`.
Same tokens as the CLI: `pipeline!(driver, "parenthost:2"; args=[…])`. A commented remote
example is at the bottom of that file (`setup!` first, or CLI `setup`).

## without_kit/

| Script | Output |
| --- | --- |
| `pi_file.jl` | `pi_results.txt` |
| `pi_echo.jl` | stdout |
| `pipeline_pi.jl` | same file via `go!` |

Run alone, via `go`, or via the `go!` API wrapper:

```bash
julia demos/without_kit/pi_echo.jl
julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl
julia --project=. demos/without_kit/pipeline_pi.jl
```

`pipeline_pi.jl` mirrors `pipeline_square.jl` for as-is jobs:
`go!(script, "parenthost:2"; args=["--n", "5000"])`. Monte Carlo samples are
`--n N` (default 1000).
A commented remote example is at the bottom of that file (`setup!` first).

Remote: set `DISTRIBUTED_REMOTE_PROJECT_ROOT` when needed. Optional: `DISTSSHKIT_HOSTS`
(comma-separated `host` or `host:N`; used by `go` / `drive` / `pipeline!`),
`SYNC_MODE=sync|rsync|off` (pipeline env).
