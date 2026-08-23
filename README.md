# DistSSHKit.jl

[English](README.md) | [日本語](README.ja.md)

[![CI](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKit.jl/graph/badge.svg?token=6OT4L5JDUW)](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[![JETLS](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/jetls.yml?branch=main&label=JETLS)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/jetls.yml)
[![E2E daily](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/ssh-e2e-daily.yml?branch=main&label=E2E%20daily)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/ssh-e2e-daily.yml)
[![Aqua](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/aqua.yml?branch=main&label=Aqua)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/aqua.yml)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Discussions](https://img.shields.io/badge/GitHub-Discussions-blueviolet?logo=github)](https://github.com/yamanori99/DistSSHKit.jl/discussions)

DistSSHKit is a kit for running the same Julia project locally and over SSH,
then collecting the results. It makes SSH-distributed runs easier and more
uniform, which helps keep those runs reproducible. It uses Distributed.jl
processes, not threads. Supported on **macOS, Linux, and WSL2 Ubuntu** (not
native Windows).

Even small labs and individuals often have a few high-performance machines or
workstations. DistSSHKit helps you use that hardware as a small set of compute
nodes. A lightweight scheduler, `DistSSHKitQueue.jl`, is also in progress.

> [!NOTE]
> **0.3.x** on General keeps today's commands. Development toward **0.4** is open
> (queue-layer hooks). Ordinary bugs still get fixed.
> [CONTRIBUTING.md](CONTRIBUTING.md#feature-freeze) ·
> [Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26).

## Install

From the Julia REPL, type `]` to enter the Pkg REPL mode and run:

```julia
pkg> add DistSSHKit
```

Or, equivalently, via the `Pkg` API:

```julia
julia> import Pkg; Pkg.add("DistSSHKit")
```

The machine running the kit also needs **`ssh`**, **`rsync`**, and (only for git
deploys) **`git`** — `pkg> add` does not install them. Full requirements:
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/).

For everything else, see the **[Documentation](https://yamanori99.github.io/DistSSHKit.jl/stable/)**.

## Usage

### Basic terms

- **Host** — the machine that runs the work. This job's DistSSHKit parent is
  `parenthost`. An SSH target is `user@hostname`, an IP address, or an SSH
  config `Host` alias. `parenthost` is this job's DistSSHKit parent (the Julia
  process that parsed the token when you start the kit yourself)
- **Process** — one running `julia`. Each process has its own memory and runs
  independently at the OS level
  (this kit launches multiple `julia` processes, even on a single machine, to run
  work in parallel — built on Distributed.jl)
- **Master** — the process on `parenthost` that plans slots (`go`) or hands
  work to workers (`drive`) and collects results. When a queue starts that
  process, `parenthost` is the queue's runner, not your client machine
- **Worker** — a process that receives work from the master and runs it

Example: when you run `go` / `drive` on your own machine, that machine is
`parenthost`. Each machine can run several workers (`parenthost` may run
none), and you can add as many remote machines as you like.

<!-- markdownlint-disable MD033 -->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/src/assets/diagram/topology-dark.svg">
    <img alt="Drive topology: Master process on parenthost, workers on parenthost and remotes" src="docs/src/assets/diagram/topology.svg">
  </picture>
</p>
<!-- markdownlint-enable MD033 -->

The diagram is **drive**: one Master process on `parenthost`, workers on
`parenthost` and remotes. **go** uses the same `parenthost` token, but each
host runs independent slots (not Distributed workers).

There's no limit on the number of remote hosts — more hosts just means more time
spent on SSH connections and deployment, so it's best to start with a few and
scale up from there.

Before you use a remote host, it needs:

- Passwordless SSH login from `parenthost`
- Julia installed, with the **same major.minor version** as `parenthost`
  (checked by `setup --check`)

Details: [Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/).

> [!TIP]
> If SSH disconnects are a worry, use machines that stay up, and keep the master
> session alive with something like `tmux`.

### go and drive

There are two ways to run a script:

- **go** — each host runs your `.jl` as-is from start to finish
- **drive** — one master farms work to workers (built on Distributed.jl)

`go` alone is plenty useful. A common path is to first check a standalone run
with `go`, then move to `drive` / Distributed.jl when you need it.

### How you call it

- **CLI** — invoke the kit from the terminal.
  Example: `julia --project=. -m DistSSHKit go user@host1:1 script.jl`.
  Good for a quick try or a shell script
- **Julia** — call functions from your own Julia code (a script, the REPL, or
  another package): `setup!`, `go!` / `drive!`, and other `!` functions
- **`distsshkit` (experimental)** — after `pkg> app add DistSSHKit`, a
  `distsshkit` command on the terminal. Same flags as `-m`, but always the Apps
  copy, not `--project=.`. Fine for `go` / `setup` / `demo`; keep `drive` and
  `size` on `julia --project=. -m DistSSHKit`. When to use it:
  [User Guide](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/distsshkit/)

CLI flags map one-to-one onto the Julia API: `setup --rsync` is
`setup!(session, :rsync)`.
See [`demos/with_kit/pipeline_square.jl`](demos/with_kit/pipeline_square.jl) and
[`demos/without_kit/pipeline_pi.jl`](demos/without_kit/pipeline_pi.jl).

Both do the same thing — only the calling convention differs. The CLI is the
easiest place to start.

### Preparing remotes

You need `setup` before running a script. It deploys your local Julia project to
each remote and installs dependencies. Pick one deploy/init action per
invocation.

- First deploy: either `--rsync` (send the local tree as-is) or `--clone`
  (`git clone` a repository) — pick one
- Dependencies: `--instantiate` (`Pkg.instantiate` on the remote)
- Update (redeploy): `--sync` (`git push`, then `pull` on each remote),
  `--pull` (`pull` only, no push), or `--rsync` again
- Other modes:
  - `--check` (verify SSH / Julia / dependencies)
  - `--cleanup` (kill leftover worker processes)
  - `--delete` (remove the remote project directory — destructive)

`--rsync` / `--clone` / `--sync` / `--pull` / `--delete` all ask for confirmation
before running. Pass `-y` / `--yes` to run non-interactively, e.g. from a script.

Details: [setup](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/setup/).

> [!NOTE]
> **Not sure whether to use rsync or git?**
>
> - **`--rsync`** — just sends your local files as-is; no git needed on the
>   remote. Good for a first try or a one-off run
> - **`--clone` then `--sync`** — manages the remote as a git repository. Better
>   if you're updating the code continuously, or you want `drive --require-git`
>   to confirm the remote commit matches your local one for reproducibility

A typical first-time setup (rsync path) looks like this:

```bash
# Copy the files over
julia --project=. -m DistSSHKit setup --rsync user@host1 user@host2
# Install dependencies
julia --project=. -m DistSSHKit setup --instantiate user@host1 user@host2
# Sanity check
julia --project=. -m DistSSHKit setup --check user@host1 user@host2
```

Other commands that come in handy:

```bash
# Clean up leftover worker processes
julia --project=. -m DistSSHKit setup --cleanup user@host1 user@host2
# Start over from scratch (asks for confirmation)
julia --project=. -m DistSSHKit setup --delete user@host1 user@host2
```

### Examples

After setup, run like this.

**CLI, go.** One full run of `script.jl` on each host (`parenthost:N` also works).

```bash
julia --project=. -m DistSSHKit go user@host1:1 user@host2:1 path/to/script.jl
```

**CLI, drive.** For a git deploy, later updates are `setup --sync`. `rsync` works
too.

```bash
julia --project=. -m DistSSHKit drive parenthost:2 user@host1:4 path/to/driver.jl
```

**Julia, go.** Keep `remote=` consistent with `setup!` (omit both for the default
path).

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["user@host1"], remote=remote, yes=true)
setup!(session, :rsync, :instantiate)
go!("path/to/script.jl", "user@host1:1"; remote=remote)
```

**Julia, drive.**

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["user@host1"], remote=remote, yes=true)
setup!(session, :clone; repo="https://github.com/org/proj.git")
setup!(session, :instantiate)
drive!("path/to/driver.jl", "parenthost:2", "user@host1:4"; remote=remote)
setup!(session, :sync)  # later updates
```

`pipeline!` is an optional one-shot: sync → `size!` → `drive!` → collect.
It does not run `setup!`; prepare remotes first.
Details: [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/).

### Try a demo

Bundled examples so you can try the kit without writing a script first:

```bash
julia --project=. -m DistSSHKit demo install with_kit
```

```bash
julia --project=. -m DistSSHKit drive parenthost:2 demos/with_kit/square_file.jl
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

Bugs and feature requests: [Issues](https://github.com/yamanori99/DistSSHKit.jl/issues).
Questions and ideas: [Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute.

## License

Source code is [MIT](LICENSE). The Julia dots in the project logo and diagrams
are Copyright (c) 2012-2022 Stefan Karpinski,
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
DistSSHKit adapts them. Details: [LICENSE](LICENSE) and
[julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics).

<!-- markdownlint-disable MD033 -->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/src/assets/logo/logo-dark-static.svg">
    <img src="docs/src/assets/logo/logo-static.svg" width="180" alt="DistSSHKit.jl logo"/>
  </picture>
</p>
<!-- markdownlint-enable MD033 -->
