# [plan](@id Manual-plan)

Inspect a script. Does **not** start a job. Suggests `go`, `ride`, or
`drive` from syntax (`map` / `filter` / comprehension, `for` as out of
scope, Distributed vocabulary → `drive`).

```bash
julia --project=. -m DistSSHKit plan SCRIPT.jl
julia --project=. -m DistSSHKit plan parent --gb-per-worker 1.5 SCRIPT.jl
```

Optional slot estimate uses [`size!`](@ref) (`--gb-per-worker`, `--probe`,
or host tokens). Default is syntax only (no RSS probe). `size` CLI stays.

Also: `plan --help`. API: [`plan`](@ref) (no bang).

`ride` is experimental ([`ride!`](@ref) / CLI `ride`). A `:ride` suggestion
means syntax looks distributable; runtime still checks `:effect_free`.

Flag vocabulary: [User Guide](@ref Manual).
