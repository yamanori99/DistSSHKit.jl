# DistSSHKit.jl

[English](README.md) | [日本語](README.ja.md)

<!-- markdownlint-disable MD013 -->
[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/CI.yml?branch=main&style=flat-square&logo=githubactions&logoColor=white&label=Test)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[![Codecov](https://img.shields.io/codecov/c/github/yamanori99/DistSSHKit.jl?style=flat-square&logo=codecov&logoColor=white)](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[![docs-stable](https://img.shields.io/badge/docs-stable-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[![docs-dev](https://img.shields.io/badge/docs-dev-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
[![Discussions](https://img.shields.io/badge/GitHub-Discussions-blueviolet?style=flat-square&logo=github)](https://github.com/yamanori99/DistSSHKit.jl/discussions)
<!-- markdownlint-enable MD013 -->

DistSSHKit is a kit for running the same Julia project locally and over SSH,
then collecting the results. It makes SSH-distributed runs easier and more
uniform, which helps keep those runs reproducible. It uses Distributed.jl
processes, not threads. Supported on **macOS, Linux, and WSL2 Ubuntu** (not
native Windows).

Even small labs and individuals often have a few high-performance machines or
workstations. DistSSHKit helps you use that hardware as a small set of
compute nodes. To run one after another, see
[DistSSHQueue.jl](https://github.com/yamanori99/DistSSHQueue.jl).

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

For everything else, see the
**[Documentation](https://yamanori99.github.io/DistSSHKit.jl/stable/)**.

## Usage

### Basic terms

- **Host** — a machine. Here you specify it as a host token like `parent`
  or `child:user@hostname`.
- **Process** — one running `julia`. Each process has its own memory and
  runs independently at the OS level.
  (This kit launches multiple `julia` processes, even on a single machine, to
  run work in parallel — built on Distributed.jl)
- **Master** — the process on the kit parent that plans slots (`go`) or hands
  work to workers (`drive`) and collects results. The kit parent is the machine
  that started that process.
- **Worker** — a process that receives work from the master and runs it.

Example: when you run `go` / `drive` on your own machine, that machine is
the kit parent. Each machine can run several workers (the kit parent may run
none), and you can add as many remote machines as you like.

<!-- markdownlint-disable MD033 -->
<p align="center">
  <picture>
    <source
      media="(prefers-color-scheme: dark)"
      srcset="docs/src/assets/diagram/topology-dark.svg">
    <img
      alt="Drive topology: master and workers"
      src="docs/src/assets/diagram/topology.svg">
  </picture>
</p>
<!-- markdownlint-enable MD033 -->

The diagram is **drive**. One master on the kit parent, workers on each host.
**go** uses the same host tokens, but there is no
master/worker: each host runs the script on its own.

```text
parent                 # kit parent
parent:2               # two on the kit parent
child:user@hostname    # SSH child (user@host, IP, or Host alias)
child:user@hostname:4  # four on that child
```

There's no limit on the number of SSH hosts — more hosts just means more time
spent on SSH connections and deployment, so it's best to start with a few and
scale up from there.

Before you use an SSH host, it needs:

- Passwordless SSH login from the kit parent
- Julia installed, with the **same major.minor version** as the kit parent
  (checked by `setup --check`)

Details:
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/).

> [!TIP]
> DistSSHKit runs one job while you stay connected.
> [DistSSHQueue.jl](https://github.com/yamanori99/DistSSHQueue.jl)
> (`pkg> add DistSSHQueue`) lets you line jobs up on a machine that stays on,
> so a dropped connection does not stop the run. DistSSHKit still does the
> running. `tmux` can keep a job that is already running. It will not look
> after jobs that come later.

### go and drive

There are two ways to run a script:

- **go** — each host runs your `.jl` as-is from start to finish
- **drive** — one master farms work to workers (built on Distributed.jl)

`go` alone is plenty useful. A common path is to first check a standalone run
with `go`, then move to `drive` / Distributed.jl when you need it.

### How you call it

- **CLI** — invoke the kit from the terminal.
  Example: `julia --project=. -m DistSSHKit go child:user@host1:1 script.jl`.
  Good for a quick try or a shell script
- **Julia** — call functions from your own Julia code (a script, the REPL, or
  another package): `setup!`, `go!` / `drive!`, and other `!` functions
- **`distsshkit` (experimental)** — after `pkg> app add DistSSHKit`, a
  `distsshkit` command on the terminal. Same flags as `-m`, but always the Apps
  copy, not `--project=.`. Fine for `go` / `setup` / `demo`; keep `drive` and
  `size` on `julia --project=. -m DistSSHKit`. When to use it, see
  [the distsshkit page][ug-app].

CLI flags map one-to-one onto the Julia API: `setup --rsync` is
`setup!(session, :rsync)`.
See [`demos/with_kit/pipeline_square.jl`](demos/with_kit/pipeline_square.jl) and
[`demos/without_kit/pipeline_pi.jl`](demos/without_kit/pipeline_pi.jl).

Both do the same thing — only the calling convention differs. The CLI is the
easiest place to start.

### Preparing remotes

Usually you run `setup` before a script: it deploys the project and installs
dependencies. Pick one deploy/init action per invocation. On an empty/missing
remote, `go --rsync` / `drive --rsync` can copy and instantiate in one shot
(default `go` / `drive` still expect remotes already prepared).

- First deploy: either `--rsync` (send the local tree as-is) or `--clone`
  (`git clone` a repository) — pick one
- Dependencies: `--instantiate` (`Pkg.instantiate` on the remote)
- Update (redeploy): `--sync` (`git push`, then `pull` on each remote),
  `--pull` (`pull` only, no push), or `--rsync` again
- Other modes:
  - `--check` (verify SSH / Julia / dependencies)
  - `--cleanup` (kill leftover worker processes)
  - `--delete` (remove the remote project directory — destructive)

`--rsync` / `--clone` / `--sync` / `--pull` / `--delete` all ask for
confirmation before running. Pass `-y` / `--yes` to run non-interactively,
e.g. from a script.

Details:
[setup](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/setup/).

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

**CLI, go.** One full run of `script.jl` on each host (`parent:N` also works).

```bash
julia --project=. -m DistSSHKit go \
  child:user@host1:1 child:user@host2:1 path/to/script.jl
```

**CLI, drive.** For a git deploy, later updates are `setup --sync`.
`rsync` works too.

```bash
julia --project=. -m DistSSHKit drive \
  parent:2 child:user@host1:4 path/to/driver.jl
```

**Julia, go.** Keep `remote=` consistent with `setup!` (omit both for
the default path).

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :rsync, :instantiate)
go!("path/to/script.jl", "child:user@host1:1"; remote=remote)
```

**Julia, drive.**

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :clone; repo="https://github.com/org/proj.git")
setup!(session, :instantiate)
drive!("path/to/driver.jl", "parent:2", "child:user@host1:4"; remote=remote)
setup!(session, :sync)  # later updates
```

`pipeline!` is an optional one-shot: sync → `size!` → `drive!` → collect.
It does not run `setup!`. `sync=:rsync` there copies only (no instantiate);
prepare remotes first, or use `drive!(…; sync=:rsync)`.
Details: [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/).

### Try a demo

Bundled examples so you can try the kit without writing a script first.
`with_kit` is drive; `without_kit` is standalone / go:

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo install without_kit
```

```bash
julia --project=. -m DistSSHKit drive parent:2 demos/with_kit/square_file.jl
julia --project=. -m DistSSHKit go parent:2 demos/without_kit/pi_file.jl
```

Walkthrough:
[Demo](https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/demo/).

## Documentation

- Introduction:
  [Introduction](https://yamanori99.github.io/DistSSHKit.jl/stable/)
- First Steps:
  [First Steps](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
- User Guide:
  [User Guide](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/)
- API: [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/)
- News: [NEWS.md](NEWS.md)

## Contributing

Bugs and feature requests:
[Issues](https://github.com/yamanori99/DistSSHKit.jl/issues).
Questions and ideas:
[Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute.

## License

Source code is [MIT](LICENSE). The Julia dots in the project logo and diagrams
are Copyright (c) 2012-2022 Stefan Karpinski,
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
DistSSHKit adapts them. Details: [LICENSE](LICENSE) and
[julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics).

[ug-app]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/distsshkit/

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img
    src="docs/src/assets/logo/logo-static.svg#gh-light-mode-only"
    width="180"
    alt="DistSSHKit.jl logo"/>
  <img
    src="docs/src/assets/logo/logo-dark-static.svg#gh-dark-mode-only"
    width="180"
    alt="DistSSHKit.jl logo"/>
</p>
<!-- markdownlint-enable MD033 -->
