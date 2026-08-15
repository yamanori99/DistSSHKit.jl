# DistSSHKit.jl

[![CI](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKit.jl/graph/badge.svg?token=6OT4L5JDUW)](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/jetls.yml)
[![E2E daily](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/ssh-e2e-daily.yml?branch=main&label=E2E%20daily)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/ssh-e2e-daily.yml)
[![Aqua](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/aqua.yml?branch=main&label=Aqua)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/aqua.yml)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[![Julia (API) 1.10+](https://img.shields.io/badge/Julia_(API)-1.10+-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/stable/api/)
[![Julia (CLI) 1.12+](https://img.shields.io/badge/Julia_(CLI)-1.12+-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

DistSSHKit makes it easy to run one Julia project locally and over SSH, then
collect the results. It uses Distributed.jl processes (not threads). **macOS,
Linux, and WSL2 Ubuntu** (not native Windows).

These days, even small labs and individuals often have several high-performance
machines or workstations. DistSSHKit helps you put that hardware to work.

## Install

From the Julia REPL, type `]` to enter the Pkg REPL mode and run:

```julia
pkg> add DistSSHKit
```

Or, equivalently, via the `Pkg` API:

```julia
julia> import Pkg; Pkg.add("DistSSHKit")
```

Also needs **`ssh`**, **`rsync`**, and **`git`** (git deploy only) on the
machine where you run the kit; `pkg> add` does not install them.
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/).

Optional (Julia **1.12+**, [Pkg Apps](https://pkgdocs.julialang.org/v1/apps/),
experimental): a PATH shim that always runs the **Apps** copy of DistSSHKit,
not the kit in the current project. For the project kit, keep
`julia --project=. -m DistSSHKit`.

```julia
pkg> app add DistSSHKit
```

If `~/.julia/bin` is on `PATH` (Pkg warns when it is not):

```bash
distsshkit --help
```

Same arguments as `julia -m DistSSHKit`. Fits `go` / `setup` / `demo`. For
`drive` / `size`, use `julia --project=. -m DistSSHKit` so workers use the job
project.

Install, demo, `go` / `drive`, remote hosts, and API: **[Documentation](https://yamanori99.github.io/DistSSHKit.jl/stable/)**.

## Jobs and launchers

Two job shapes and two launchers. Host tokens are the same everywhere
(`local:2`, `user@host:1`). CLI needs Julia **1.12+** (`julia -m DistSSHKit …`).
The library API works on **1.10+**.

Job shapes:

- **go** — each host runs your `.jl` from start to finish
- **drive** — one master farms work to Distributed.jl workers

Launchers:

- **CLI** — `julia -m DistSSHKit …` (`setup`, `go`, `drive`, …)
- **Julia** — `setup!`, `go!` / `drive!`, … from a script or the REPL
  (`setup!` mirrors `setup --…`)

CLI — go (first deploy with rsync; one setup mode per invocation):

```bash
julia --project=. -m DistSSHKit setup --rsync user@host1
julia --project=. -m DistSSHKit setup --instantiate user@host1
julia --project=. -m DistSSHKit go user@host1:1 user@host2:1 path/to/script.jl
```

CLI — drive (git remotes; first deploy with `--clone`, later `--sync`):

```bash
julia --project=. -m DistSSHKit setup --clone user@host1
julia --project=. -m DistSSHKit setup --instantiate user@host1
julia --project=. -m DistSSHKit drive local:2 user@host1:4 path/to/driver.jl
# later updates: setup --sync user@host1
```

Julia — go (`remote=` must match `setup!`; omit both to use the default path):

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["user@host1"], remote=remote, yes=true)
setup!(session, :rsync, :instantiate)
go!("path/to/script.jl", "user@host1:1"; remote=remote)
```

Julia — drive:

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["user@host1"], remote=remote, yes=true)
setup!(session, :clone; repo="https://github.com/org/proj.git")
setup!(session, :instantiate)
drive!("path/to/driver.jl", "local:2", "user@host1:4"; remote=remote)
# later: setup!(session, :sync)
```

`pipeline!` is optional sugar: optional sync → `size!` → `drive!` → optional
collect. It does not run `setup!`; prepare remotes first.
Details: [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/).

### Try a demo

Bundled examples so you can try the kit without writing a job first:

```bash
julia --project=. -m DistSSHKit demo install
```

```bash
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
```

Walkthrough: [Demo](https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/demo/).

## Documentation

| | |
| --- | --- |
| Introduction | [Introduction](https://yamanori99.github.io/DistSSHKit.jl/stable/) |
| First Steps | [First Steps](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/) |
| User Guide | [User Guide](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/) |
| API | [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/) |
| News | [NEWS.md](NEWS.md) |

## Contributing

Bugs and features to track: [Issues](https://github.com/yamanori99/DistSSHKit.jl/issues).
Questions, ideas, and other chat: [Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute.

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="docs/src/assets/logo/logo-static.svg" width="180" alt="DistSSHKit.jl logo"/>
</p>
<!-- markdownlint-enable MD033 -->
