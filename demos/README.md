# demos/

Two groups — same layout after `demo install`:

| Path | Role | Command |
| --- | --- | --- |
| [`with_kit/`](with_kit/) | Driver scripts (`init` / `main`) | `drive` or `pipeline!` |
| [`without_kit/`](without_kit/) | Standalone Julia scripts | `julia …` or `go` |

```text
demos/
  with_kit/
    square_file.jl      # file: square_results.csv
    square_echo.jl      # stdout only
    pipeline_square.jl  # API: pipeline!(driver=square_file.jl)
  without_kit/
    pi_file.jl          # file: pi_results.txt
    pi_echo.jl          # stdout only
```

Naming: `{topic}_{file|echo}` — `*_file` writes a file, `*_echo` prints only.
`pipeline_square.jl` wraps `square_file.jl` through the `pipeline!` API.

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_echo.jl
julia --project=. demos/with_kit/pipeline_square.jl
julia demos/without_kit/pi_echo.jl
julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl
```

## with_kit/

| Script | Output |
| --- | --- |
| `square_file.jl` | `square_results.csv` |
| `square_echo.jl` | stdout |
| `pipeline_square.jl` | same CSV via `pipeline!` |

Drivers use `init_output_dir!` + `main` + `pmap`. Optional hooks: `drive --help`.
`pipeline_square.jl` is the thin API entry (sync → drive → collect) over `square_file.jl`.

## without_kit/

| Script | Output |
| --- | --- |
| `pi_file.jl` | `pi_results.txt` |
| `pi_echo.jl` | stdout |

Run alone or via `go`:

```bash
julia demos/without_kit/pi_echo.jl
julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl
```

Remote: set `DISTRIBUTED_REMOTE_PROJECT_ROOT` when needed. Optional: `DISTSSHKIT_HOSTS`
(comma-separated `host` or `host:N`; used by `go` / `drive` / `pipeline!`),
`SYNC_MODE=sync|rsync|off` (pipeline env).
