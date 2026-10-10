# DistSSHKit.jl

[English](README.md) | [日本語](README.ja.md)

<!-- markdownlint-disable MD013 -->
[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/CI.yml?branch=main&style=flat-square&logo=githubactions&logoColor=white&label=Test)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[![PkgEval](https://juliaci.github.io/NanosoldierReports/pkgeval_badges/D/DistSSHKit.square.svg)](https://juliaci.github.io/NanosoldierReports/pkgeval_badges/D/DistSSHKit.html)
[![Codecov](https://img.shields.io/codecov/c/github/yamanori99/DistSSHKit.jl?style=flat-square&logo=codecov&logoColor=white)](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[![docs-stable](https://img.shields.io/badge/docs-stable-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[![docs-dev](https://img.shields.io/badge/docs-dev-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
[![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
[![Discussions](https://img.shields.io/badge/GitHub-Discussions-blueviolet?style=flat-square&logo=github)](https://github.com/yamanori99/DistSSHKit.jl/discussions)
<!-- markdownlint-enable MD013 -->

DistSSHKit is a toolkit for running the same Julia project on your local
machine and on remote machines over SSH, and for collecting the results. It
simplifies and standardizes the steps of SSH-distributed execution, which makes
runs easier to reproduce. It parallelizes with Distributed.jl processes rather
than threads. Supported platforms are **macOS, Linux, and WSL2 Ubuntu** (native
Windows is not supported).

Even small labs and individual researchers often own a few high-performance
machines or workstations. DistSSHKit lets you combine them into a small compute
cluster.

A single `pkg> add DistSSHKit` is all you need to install it. That one package
covers both running a job immediately and running jobs from a queue. DistSSHKit
consists of two parts, and the command is `julia -m DistSSHKit`.

- **[DistSSHRun](https://yamanori99.github.io/DistSSHRun.jl/stable/)** runs a
  job immediately from the machine where you launch it. The SSH connection
  stays open until the job finishes. Its commands are `setup`, `go`, `ride`,
  `drive`, `plan`, `size`, and `pool`. You can keep the session alive with
  `tmux`, but the connection itself must stay up as well.
- **[DistSSHQueue](https://yamanori99.github.io/DistSSHQueue.jl/stable/)**
  accumulates jobs on an always-on machine and runs them one after another.
  Install the same package there. Once a job is in the queue, it keeps running
  even if your laptop disconnects.

## Install

From the Julia REPL, press `]` to enter Pkg mode and run:

```julia
pkg> add DistSSHKit
```

Or, equivalently, use the `Pkg` API:

```julia
julia> import Pkg; Pkg.add("DistSSHKit")
```

The machine that runs the kit also needs **`ssh`** and **`rsync`**, as well as
**`git`** if you use git deployment. `pkg> add` does not install these. For the
full list of requirements, see
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/).

For everything else, see the
**[Documentation](https://yamanori99.github.io/DistSSHKit.jl/stable/)**.

## Usage

### Basic terms

- **Host** — a machine that does the computation. You specify it with a token
  such as `parent` or `child:user@hostname`.
- **Process** — a single running `julia` instance. Each process has its own
  memory and runs independently at the OS level.
  (The kit launches multiple `julia` processes to run work in parallel, even on
  a single machine. It is built on Distributed.jl.)
- **Master** — the process on the kit parent. With `go`, it plans the slots;
  with `drive`, it hands work to the workers and collects the results. The kit
  parent is the machine that started this process.
- **Worker** — a process that receives work from the master and runs it.

For example, if you run `go` or `drive` on your own machine, that machine is the
kit parent. Each machine can run several workers (the kit parent may run none),
and you can add as many remote machines as you like.

<!-- markdownlint-disable MD033 MD013 -->
<p align="center">
  <picture>
    <source
      media="(prefers-color-scheme: dark)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/diagram/topology-dark.svg">
    <source
      media="(prefers-color-scheme: light)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/diagram/topology.svg">
    <img
      alt="Drive topology: master and workers"
      src="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/diagram/topology.png">
  </picture>
</p>
<!-- markdownlint-enable MD033 MD013 -->

The diagram shows **drive**: one master on the kit parent and workers on each
host. **go** uses the same host tokens, but there is no master/worker
relationship; each host runs the script on its own.

```text
parent                 # kit parent
parent:2               # two on the kit parent
child:user@hostname    # SSH child (user@host, IP, or Host alias)
child:user@hostname:4  # four on that child
```

There is no limit on the number of SSH hosts. More hosts do mean more time spent
on SSH connections and deployment, so it is best to start with a few and scale
up from there.

Before you use an SSH host, make sure it meets the following conditions:

- You can log in from the kit parent over SSH without a password.
- Julia is installed, with the **same major.minor version** as on the kit parent
  (`setup --check` verifies this).

For details, see
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/).

### Run now: go, ride, drive

There are three ways to run a script:

- **go** — each host runs your `.jl` file as is, from start to finish.
- **ride** — the kit splits up independent `map`, filter, comprehension, or
  indexed `for` work (experimental; works on the parent or SSH workers).
- **drive** — one master distributes work to workers (built on Distributed.jl).

### Inspect: plan (files) and pool (hosts)

- **plan** — inspects a `.jl` file and suggests go, ride, or drive. It only
  reads from disk and parses, so it has no bang and does no SSH. An optional
  slot estimate can call `size!`.
- **pool** / **pool!** — reports the cores and RAM of the listed hosts. It uses
  SSH, hence the bang. It does not report RSS. Unreachable hosts stay in the
  list with `ok=false`.

**size** / **size!** reports occupancy (an RSS-based `WorkerPlan`). The CLI
`size` prints a plan. For go, drive, and ride, every listed token requires `:N`
(with no tokens, you get one slot on the parent).
`go --repeat` is the exception: it lets you omit `:N` for listed hosts, which
leaves their pool uncapped. None of
these is a dashboard.

`go` alone is already quite useful. A common workflow is to confirm a standalone
run with `go` first, then move on to `drive` and Distributed.jl when you need
them. `plan` may even suggest `ride` right away.

### Ways to call the kit

- **CLI** — run the kit directly from the terminal.
  Example: `julia --project=. -m DistSSHKit go child:user@host1:1 script.jl`.
  This suits quick experiments and shell scripts.
- **Julia** — call functions from your own Julia code (a script, the REPL, or
  another package): `setup!`, `go!`, `drive!`, `plan` (no bang), `pool!`, and
  the other `!` functions.
- **`distsshkit` (experimental)** — after `pkg> app add DistSSHKit`, you get a
  `distsshkit` command in the terminal. It takes the same flags as `-m`, but it
  always uses the copy installed as an app, not `--project=.`. It works for
  `go`,
  `setup`, and `demo`; for `drive`, `size`, and `pool`, keep using
  `julia --project=. -m DistSSHKit`. For guidance on when to use it, see
  [the distsshkit page][ug-app].

CLI flags map one-to-one onto the Julia API. For example, `setup --rsync`
corresponds to `setup!(session, :rsync)`.
After `demo install with_kit` and `demo install without_kit`, see
`distsshkit_demos/with_kit/pipeline_square.jl` and
`distsshkit_demos/without_kit/pipeline_pi.jl` for examples.

Both approaches do the same thing; only the way you call them differs. The CLI
is the easiest place to start.

### Preparing remotes

Normally you run `setup` before a script. It deploys the project and installs
dependencies. Specify only one deploy or init action per invocation. On an empty
or missing remote, `go --rsync` or `drive --rsync` can copy the project and
instantiate it in one step (plain `go` and `drive` still assume the remotes are
already prepared).

- First deployment: use either `--rsync` (send the local tree as is) or
  `--clone` (run `git clone` on a repository), not both.
- Dependencies: `--instantiate` (runs `Pkg.instantiate` on the remote).
- Updating (redeploying): `--sync` (`git push`, then `pull` on each remote),
  `--pull` (`pull` only, no push), or `--rsync` again.
- Other modes:
  - `--check` (verifies SSH, Julia, and dependencies)
  - `--cleanup` (kills leftover worker processes)
  - `--prune` (removes the `.distsshkit` go, drive, setup, and runs leaves; the
    deployed tree is kept)
  - `--delete` (removes the remote project directory; destructive)

`--rsync`, `--clone`, `--sync`, `--pull`, `--delete`, `--prune`, `up`, and
`up update` all ask for confirmation before running. Pass `-y` or `--yes` to run
them non-interactively, for example from a script.

For details, see
[setup](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/setup/).

> [!NOTE]
> **Not sure whether to use rsync or git?**
>
> - **`--rsync`** — simply sends your local files as is. The remote does not
>   need git. It suits a first try or a one-off run.
> - **`--clone` then `--sync`** — manages the remote as a git repository. This
>   is better if you update the code continuously, or if you want
>   `drive --require-git` to confirm that the remote commit matches your local
>   one for reproducibility.

A typical first-time setup (rsync route) looks like this:

```bash
# Copy the files over
julia --project=. -m DistSSHKit setup --rsync child:user@host1 child:user@host2
# Install dependencies
julia --project=. -m DistSSHKit setup --instantiate child:user@host1 child:user@host2
# Sanity check
julia --project=. -m DistSSHKit setup --check child:user@host1 child:user@host2
```

Other commands that come in handy:

```bash
# Remove go/drive/setup/runs leaves (keeps the project tree)
julia --project=. -m DistSSHKit setup --prune child:user@host1 child:user@host2
# Clean up leftover worker processes
julia --project=. -m DistSSHKit setup --cleanup child:user@host1 child:user@host2
# Start over from scratch (asks for confirmation)
julia --project=. -m DistSSHKit setup --delete child:user@host1 child:user@host2
```

### Examples

After setup, run your scripts as follows.

**CLI, go.** Each slot runs `script.jl` once, from start to finish.
`child:user@host:1` means one run on that host, and `parent:N` means N runs on
the kit parent. `--repeat N` means N runs in total, spread across the listed
hosts.

```bash
julia --project=. -m DistSSHKit go \
  child:user@host1:1 child:user@host2:1 path/to/script.jl
julia --project=. -m DistSSHKit go --repeat 100 path/to/script.jl
julia --project=. -m DistSSHKit go --repeat 100 \
  child:user@host1 child:user@host2 path/to/script.jl
```

**CLI, drive.** For a git deployment, later updates are done with
`setup --sync`. `rsync` works too.

```bash
julia --project=. -m DistSSHKit drive \
  parent:2 child:user@host1:4 path/to/driver.jl
```

**Julia, go.** Keep `remote=` consistent with `setup!` (omit both to use the
default path).

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

`pipeline!` is an optional convenience that chains sync, `drive!`, and collect
in one call. It does not run `setup!`, and its `sync=:rsync` only copies files
without instantiating. Prepare the remotes beforehand, or use
`drive!(…; sync=:rsync)`.
For details, see [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/).

### Try a demo

The bundled demos let you try the kit before writing a script of your own.
`with_kit` demonstrates drive; `without_kit` demonstrates standalone runs
and go.

Run them from a **job** project (one where you have run
`pkg> add DistSSHKit`), not from the DistSSHKit checkout:

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo install without_kit
```

```bash
julia --project=. -m DistSSHKit drive parent:2 distsshkit_demos/with_kit/square_file.jl
julia --project=. -m DistSSHKit go parent:2 distsshkit_demos/without_kit/pi_file.jl
```

For a walkthrough, see
[Demo](https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/demo/).

### Queue

```text
  client (dev machine, no cap)            queue host (always on, log in here)
  ----------------------------            ------------------------------------
  yours / a colleague's                   FIFO     one job at a time
       |                                  table    ~/.distsshqueue
       |  julia --project=.               julia -m DistSSHKit
       |    -m DistSSHKit                  qhost setup / add-host
       |    qhost:HOST submit              qhost serve
       |    status | fetch | cancel        qhost enable  after reboot
       +--------------------------------> then go / ride / drive
                                          -> workers (parent / child:)
```

**Queue host.** Log in to the always-on macOS or Linux machine and install the
same package there with `pkg> add DistSSHKit`. Every command you run on this
machine starts with the word `qhost`, and a `qhost:HOST` token is rejected. The
default Julia environment is enough, so do not pass `--project=.`:

```bash
julia -m DistSSHKit qhost setup
julia -m DistSSHKit qhost add-host parent child:host1
julia -m DistSSHKit qhost serve
```

`qhost enable` makes `serve` start again after a reboot.

**Client.** Stay on the machine that holds the job. `qhost:HOST` is the SSH name
of the queue host, and you put it on `submit`, `status`, `fetch`, and `cancel`.
That connection uses `~/.distsshqueue/env` on the queue host. To learn how to
create that environment, see [Prepare][q-prepare].

```bash
julia --project=. -m DistSSHKit qhost:HOST submit go parent:1 distsshkit_demos/without_kit/pi_echo.jl
```

For details, see [Prepare][q-prepare], [Walkthrough][q-walk], and
[Queue][q-manual].

## Documentation

- Introduction:
  [Introduction](https://yamanori99.github.io/DistSSHKit.jl/stable/)
- First Steps:
  [First Steps](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
- Queue: [Walkthrough][q-walk]
- User Guide:
  [User Guide](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/)
- API: [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/)
- News: [NEWS.md](NEWS.md)

## Contributing

Report bugs and request features in
[Issues](https://github.com/yamanori99/DistSSHKit.jl/issues).
Ask questions and share ideas in
[Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute.

## License

The source code is released under the [MIT](LICENSE) license. The Julia dots in
the project logo and diagrams are Copyright (c) 2012-2022 Stefan Karpinski,
licensed under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
DistSSHKit uses an adapted version of them. For details, see
[LICENSE](LICENSE) and
[julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics).

[ug-app]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/distsshkit/
<!-- markdownlint-disable MD013 -->
[q-prepare]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/queue-prepare/
[q-walk]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/queue-walkthrough/
[q-manual]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/
<!-- markdownlint-enable MD013 -->

<!-- markdownlint-disable MD033 MD013 -->
<p align="center">
  <picture>
    <source
      media="(prefers-color-scheme: dark)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/logo/logo-dark-static.svg">
    <source
      media="(prefers-color-scheme: light)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/logo/logo-static.svg">
    <img
      src="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/logo/logo-static.png"
      width="180"
      alt="DistSSHKit.jl logo"/>
  </picture>
</p>
<!-- markdownlint-enable MD033 MD013 -->
