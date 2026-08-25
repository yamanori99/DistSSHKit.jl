# [Demo](@id Tutorial-Demo)

Walkthrough with the bundled examples: local first, then optional remotes
(after [Prepare](@ref Tutorial-Prepare)).

Also see [User Guide · demo](@ref Manual-demo), [go](@ref Manual-go),
[drive](@ref Manual-drive), [API](@ref API).

## Install

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo install without_kit
```

That copies `demos/with_kit/` and `demos/without_kit/`.

```text
demos/
  with_kit/          # driver scripts — use drive or pipeline!
    square_file.jl   # file: square_results.csv
    square_echo.jl   # stdout only
    pipeline_square.jl  # pipeline!(driver, "parent:2")
  without_kit/       # after `demo install without_kit`
    pi_file.jl       # file: pi_results.txt
    pi_echo.jl       # stdout only
    pipeline_pi.jl       # go!(script, "parent:2") → pi_file.jl
```

Each topic has a `*_file.jl` and `*_echo.jl` pair: same job, but `*_file.jl`
writes under the slot's `DISTRIBUTED_OUTPUT_DIR` (so `go` / `drive` can collect
results from remotes). Use `*_echo.jl` when you only want terminal output.

Keep `Project.toml` at the project root — do not add `demos/Project.toml`.

Prefer **`go`** unless you already need in-script parallelism; use **`drive`**
for driver scripts that farm work with `pmap`.

## Standalone scripts (`without_kit/`)

These run on their own — no DistSSHKit import.

```bash
julia demos/without_kit/pi_file.jl --n 5000
```

Two local slots:

```bash
julia --project=. -m DistSSHKit go parent:2 demos/without_kit/pi_file.jl --n 5000
```

Same job through the API (`go!`):

```bash
julia --project=. demos/without_kit/pipeline_pi.jl --n 5000
```

With remotes (after [First-time remotes](@ref first-time-remotes)):

```bash
julia --project=. -m DistSSHKit go \
    parent:2 child:YourHost1:2 child:YourHost2:2 \
    demos/without_kit/pi_file.jl --n 5000
```

## Driver scripts (`with_kit/`)

When you need
[`pmap`](https://docs.julialang.org/en/v1/stdlib/Distributed/#Distributed.pmap)
over workers instead of N independent script runs, use `drive` (not `go`):

```bash
julia --project=. -m DistSSHKit drive parent:2 demos/with_kit/square_file.jl --n 4
```

Same driver through the API (`pipeline!` — local workers, no sync/collect):

```bash
julia --project=. demos/with_kit/pipeline_square.jl --n 4
```

With remotes (after [First-time remotes](@ref first-time-remotes)):

```bash
julia --project=. -m DistSSHKit drive \
    parent:2 child:YourHost1:2 child:YourHost2:2 \
    demos/with_kit/square_file.jl --n 4
```

Driver contract (`init_output_dir!` / `main`) and further topics: see
[User Guide · drive](@ref Manual-drive) and [API](@ref API) (`drive!`, `pipeline!`,
`worker_pmap`).
