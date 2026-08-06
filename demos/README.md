# demos/

Two groups — same layout after `demo install`:

| Path | Role | Command |
| --- | --- | --- |
| [`with_kit/`](with_kit/) | Driver scripts (`init` / `main`) | `drive` |
| [`without_kit/`](without_kit/) | Standalone Julia scripts | `julia …` or `go` |

```text
demos/
  with_kit/
    square_file.jl   # file: square_results.csv
    square_echo.jl   # stdout only
  without_kit/
    pi_file.jl       # file: pi_results.txt
    pi_echo.jl       # stdout only
```

Naming: `{topic}_{file|echo}` — `*_file` writes a file, `*_echo` prints only.

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_echo.jl
julia demos/without_kit/pi_echo.jl
julia --project=. -m DistSSHKit go demos/without_kit/pi_file.jl
```

## with_kit/

| Script | Output |
| --- | --- |
| `square_file.jl` | `square_results.csv` |
| `square_echo.jl` | stdout |

Both use `init_output_dir!` + `main` + `pmap`. Optional hooks (`prepare_workers!`, custom I/O) are in `drive --help`.

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
