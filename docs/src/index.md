# [DistSSHKit.jl](@id DistSSHKit.jl)

DistSSHKit makes it easy to run one Julia project locally and over SSH, then
collect the results. It uses Distributed.jl processes (not threads). **macOS
and Linux.**

These days, even small labs and individuals often have several high-performance
machines or workstations. DistSSHKit helps you put that hardware to work.

## What is DistSSHKit?

Two ways to run:

- **Same script on each machine** (`go`) — each host runs your `.jl` from start
  to finish. No rewrite needed. Prefer this when every run is already a complete
  job.
- **One machine coordinates** (`drive`) — your main Julia process stays in charge
  and hands pieces of the work to the others
  ([Distributed.jl](https://docs.julialang.org/en/v1/manual/distributed-computing/)).

Around that, the kit handles remote project setup, sync, and collecting outputs.
Use it from the terminal (`julia -m DistSSHKit …`) or from Julia code / notebooks.

## Installation

!!! important
    **Under active development.** Prefer a released version from General. Use
    `rev="main"` only for the development tip.

In your Julia project (`Project.toml` at the project root). If that environment
is already active, pkg mode is enough:

```julia
(MyProject) pkg> add DistSSHKit
```

(`]` enters pkg mode; backspace returns to the Julia prompt.)

Or from the shell:

```bash
julia --project=. -e 'using Pkg; Pkg.add("DistSSHKit")'
```

For the development tip (not a release):

```julia
(MyProject) pkg> add https://github.com/yamanori99/DistSSHKit.jl.git#main
```

```bash
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/yamanori99/DistSSHKit.jl.git", rev="main")'
```

There is no separate binary — use `julia --project=. -m DistSSHKit …`.

## Next

Start at **[Requirements](@ref)**, then **[Prepare](@ref Tutorial-Prepare)**
(remotes) and the bundled **[Demo](@ref Tutorial-Demo)**.

Later: [`setup`](@ref Manual-setup), [`go`](@ref Manual-go),
[`drive`](@ref Manual-drive), and the rest of the
[User Guide](@ref Manual); or the **[API](@ref API)** to embed from Julia.
