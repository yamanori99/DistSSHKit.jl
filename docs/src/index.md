# [DistSSHKit.jl](@id DistSSHKit.jl)

DistSSHKit is a kit for running the same Julia project locally and over SSH,
then collecting the results. It makes SSH-distributed runs easier and more
uniform, which helps keep those runs reproducible. It uses Distributed.jl
processes, not threads. Supported on **macOS, Linux, and WSL2 Ubuntu** (not
native Windows).

Even small labs and individuals often have a few high-performance machines or
workstations. DistSSHKit helps you use that hardware as a small set of
compute nodes. To run one after another, see
[DistSSHQueue.jl](https://github.com/yamanori99/DistSSHQueue.jl).

## What is DistSSHKit?

Two ways to run a script:

- **Same script on each machine** (`go`) — each host runs your `.jl` from start
  to finish. No rewrite needed. Prefer this when every run is already a complete
  job.
- **One machine coordinates** (`drive`) — your main Julia process stays
  in charge and hands pieces of the work to the others
  ([Distributed.jl][dist-jl]).

Around that, the kit handles remote project setup, sync, and collecting outputs.
Use it from the terminal or from Julia code / notebooks.

How you call it is a separate choice:

- **Julia API** — `setup!` for remotes, `go!` / `drive!` to run, or
  `pipeline!` for optional sync → `size!` → `drive!` → collect (not `setup!`;
  rsync there does not instantiate)
- **CLI** — `julia --project=. -m DistSSHKit go …` / `drive …`
  (and `setup`, `demo`, …)
- **`distsshkit` (experimental)** — after `pkg> app add DistSSHKit`, a
  `distsshkit` command on the terminal. Same flags as `-m`, but always the
  Apps copy, not `--project=.`. Fine for `go` / `setup` / `demo`; keep `drive`
  and `size` on `julia --project=. -m DistSSHKit`. When to use it:
  [User Guide](@ref Manual-distsshkit).

All of these need **Julia 1.12+** ([Requirements](@ref)).

Same host tokens for go / drive / size (`parent:2`, `child:user@host:1`).
`setup` uses the SSH name with no prefix. Details:
[API](@ref API), [User Guide](@ref Manual).

## Installation

From the Julia REPL, type `]` to enter the Pkg REPL mode and run:

```julia
pkg> add DistSSHKit
```

Or, equivalently, via the `Pkg` API:

```julia
julia> import Pkg; Pkg.add("DistSSHKit")
```

Optional `distsshkit` command (**1.12+**, experimental):
[User Guide](@ref Manual-distsshkit).

Also needs **`ssh`**, **`rsync`**, and **`git`** (git deploy only);
`pkg> add` does not install them. [Requirements](@ref).

## Basic terms

- **Host** — a machine. Here you specify it as a host token like `parent`
  or `child:user@hostname`.
- **Process** — one running `julia`. Each process has its own memory and
  runs independently at the OS level.
  (This kit launches multiple `julia` processes, even on a single machine,
  to run work in parallel — built on Distributed.jl)
- **Master** — the process on the kit parent that plans slots (`go`) or hands
  work to workers (`drive`) and collects results. The kit parent is the machine
  that started that process.
- **Worker** — a process that receives work from the master and runs it.

Example: when you run `go` / `drive` on your own machine, that machine is
the kit parent. Each machine can run several workers (the kit parent may run
none), and you can add as many remote machines as you like.

```@raw html
<p style="text-align:center">
<img class="docs-light-only"
  alt="Drive topology: Master process on parent, workers on parent and remotes"
  src="assets/diagram/topology.svg">
<img class="docs-dark-only"
  alt="Drive topology: Master process on parent, workers on parent and remotes"
  src="assets/diagram/topology-dark.svg">
</p>
```

The diagram is **drive**. One master on the kit parent, workers on each host.
**go** uses the same host tokens, but there is no
master/worker: each host runs the script on its own.

```text
parent                 # kit parent
parent:2               # two on the kit parent
child:user@hostname    # SSH child (user@host, IP, or Host alias)
child:user@hostname:4  # four on that child
```

There's no limit on the number of SSH hosts — more hosts just means more
time spent on SSH connections and deployment, so it's best to start with a few
and scale up. Each SSH host needs:

- Passwordless SSH from the kit parent
- Julia with the same major.minor version as the kit parent
  (`setup --check` verifies this)

Details: [Requirements](@ref).

## Next

Start at **[Requirements](@ref)**, then **[Prepare](@ref Tutorial-Prepare)**
(remotes) and the bundled **[Demo](@ref Tutorial-Demo)**.

Later: [`setup`](@ref Manual-setup), [`go`](@ref Manual-go),
[`drive`](@ref Manual-drive), and the rest of the
[User Guide](@ref Manual); or the **[API](@ref API)** to embed from Julia.

## Contributing

Bugs and feature requests:
[Issues](https://github.com/yamanori99/DistSSHKit.jl/issues).
Questions and ideas:
[Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
See [CONTRIBUTING.md][contrib] for how to contribute.

## License

Source code is [MIT][mit-lic].
The Julia dots in the docs logo and topology diagram are Copyright (c)
2012-2022 Stefan Karpinski,
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
DistSSHKit adapts them.
[julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics).

[contrib]: https://github.com/yamanori99/DistSSHKit.jl/blob/main/CONTRIBUTING.md
[mit-lic]: https://github.com/yamanori99/DistSSHKit.jl/blob/main/LICENSE
[dist-jl]: https://docs.julialang.org/en/v1/manual/distributed-computing/
