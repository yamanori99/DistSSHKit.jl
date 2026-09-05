# [DistSSHKit.jl](@id DistSSHKit.jl)

DistSSHKit runs the same Julia project on this machine and over SSH, then
collects the results. It uses Distributed.jl processes, not threads.
Supported on **macOS, Linux, and WSL2 Ubuntu** (not native Windows).

To queue jobs on a machine that stays up, see
[DistSSHQueue.jl](https://yamanori99.github.io/DistSSHQueue.jl/stable/).

## What is DistSSHKit?

Two ways to run a script:

- **Same script on each machine** (`go`) — each host runs your `.jl` end to
  end. Prefer when every run is already a complete job.
- **One machine coordinates** (`drive`) — the main process farms work to
  the others ([Distributed.jl][dist-jl]).

The kit also covers remote project setup, sync, and collecting outputs —
from the terminal or from Julia / notebooks.

Call paths:

- **Julia API** — `setup!` for remotes, `go!` / `drive!` to run, or
  `pipeline!` for optional sync → `size!` → `drive!` → collect (not `setup!`;
  rsync there does not instantiate)
- **CLI** — `julia --project=. -m DistSSHKit go …` / `drive …`
  (and `setup`, `demo`, …)
- **`distsshkit` (experimental)** — after `pkg> app add DistSSHKit`, a
  `distsshkit` command on the terminal. Same flags as `-m`, but always the
  Apps copy, not `--project=.`. Use for `go` / `setup` / `demo`; keep `drive`
  and `size` on `julia --project=. -m DistSSHKit`. When to use it:
  [User Guide](@ref Manual-distsshkit).

All of these need **Julia 1.12+** ([Requirements](@ref)).

Same host tokens for setup / go / drive / size (`parent:2`,
`child:user@host:1`; setup / size ignore `:N`). Details:
[API](@ref API), [User Guide](@ref Manual).

## Installation

From the Julia REPL, type `]` to enter the Pkg REPL mode and run:

```julia
pkg> add DistSSHKit
```

Or: `import Pkg; Pkg.add("DistSSHKit")`.

Optional `distsshkit` command (**1.12+**, experimental):
[User Guide](@ref Manual-distsshkit).

Also needs **`ssh`**, **`rsync`**, and **`git`** (git deploy only);
`pkg> add` does not install them. [Requirements](@ref).

## Basic terms

- **Host** — a machine, given as a token like `parent` or
  `child:user@hostname`.
- **Process** — one `julia` OS process with its own memory. The kit may
  start several per machine (Distributed.jl).
- **Master** — the process on the kit parent that plans slots (`go`) or
  farms work to workers (`drive`) and collects results. The kit parent is
  the machine that started that process.
- **Worker** — a process that receives work from the master and runs it.

Example: running `go` / `drive` on your machine makes that machine the kit
parent. Each host can run several workers (including zero on the parent).
Remotes are optional.

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

No hard limit on SSH hosts; more remotes means more SSH and deploy time —
start with a few. Each SSH host needs:

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
