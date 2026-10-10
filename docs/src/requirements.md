# Requirements

Prerequisites for [Home](@ref DistSSHKit.jl) and
[Prepare](@ref Tutorial-Prepare). You can start local-only; add the remote
pieces when you SSH to other hosts. `pkg> add DistSSHKit` does not install
**`ssh`**, **`rsync`**, or **`git`**.

On this page, **this machine** means the machine the run starts from:
the computer where you run `go` or `drive`, or the queue host when the
job was left there.

Runs need **SSH between machines** (LAN or VPN is enough). Constant
internet is not required; you mainly need it for `Pkg.add` /
`instantiate`, outbound `git clone` / `git pull`, or installing Julia.

## All machines

Applies to this machine **and** each SSH host that runs
jobs.

- **macOS, Linux, and WSL2 Ubuntu** (not native Windows)
- **Julia 1.13+**
  The floor is the maintained stable. When Julia stops updating the
  previous minor, DistSSHKit moves with it (see Contributing, Julia slots).
  - Library (`Pkg.add` / `using` / `go!` / `drive!`) and CLI
    (`julia -m DistSSHKit`)
  - Same **major.minor** on this machine and SSH hosts (`setup --check`
    fails on a mismatch unless `--ignore-julia-version`; patch-only
    differences warn)
  - Prefer **[juliaup](https://github.com/JuliaLang/juliaup)** so
    `$HOME/.juliaup/bin/julia` is available (or macOS Homebrew
    `/opt/homebrew/bin/julia` / `/usr/local/bin/julia`). Otherwise put a
    1.13+ binary at a usual OS path ([Checks](@ref)) or set `--julia` /
    `JULIA_DISTRIBUTED_EXE`. On major.minor mismatch, use
    [`up`](@ref Manual-up) when juliaup is already on the
    host (official install or Homebrew; see [Checks](@ref)). Missing path
    or a related bug:
    [open an Issue](https://github.com/yamanori99/DistSSHKit.jl/issues).

WSL2 is Linux, with a few extra rules:

- Run DistSSHKit **inside** the distro, not PowerShell
- Keep the project on the Linux filesystem (`~/…`), not `/mnt/c/…`
- Install `ssh` / `rsync` / Julia inside WSL

## Remotes

No hard limit on remote hosts. More remotes means more SSH and deploy time —
start with a few.

A job started from your machine keeps that SSH connection open until it
finishes. On an always-on machine, the same `pkg> add DistSSHKit` holds jobs
and runs them in order after that connection drops.

When you use SSH hosts (not just `parent:N`):

Passwordless SSH means this machine and those hosts are **one trust
domain**: whoever can start a job as you, can run arbitrary Julia on each
listed host as that remote user. That is the intended lab premise (shared
shell access). A
[queue host](@ref Queue-manual)
widens who can trigger those runs.

**This machine** — also install:

- **`ssh`** — passwordless login to each host
- **`rsync`** — collect results (`go` / `drive`); push the project tree only
  without git (`setup --rsync`)
- **`git`** — git deploy path only (clone / push / pull); skip for rsync-only

**Each SSH host:**

- **Passwordless SSH** from this machine (repeat per host;
  use a connect timeout — bare `ssh` can hang on a bad IP). See [Checks](@ref)
  below.
- **`git`** — git deploy path only (clone / pull on the host); skip for
  rsync-only. Git vs rsync: [First Steps · Prepare](@ref Tutorial-Prepare),
  [User Guide · setup](@ref Manual-setup).

## Project

DistSSHKit assumes a Julia **project** — `Project.toml` at the project root
(not a subfolder like `demos/`):

- Run with `julia --project=.` from that directory (DistSSHKit activates the
  nearest `Project.toml` above each script). `julia -m DistSSHKit` from a
  project that only *depends on* DistSSHKit uses that job's `Project.toml`,
  not DistSSHKit's own (`DISTRIBUTED_PROJECT_ROOT` overrides).
- Declare dependencies in that `Project.toml` / `Manifest.toml`. Install them on
  **every** machine that runs jobs: local `Pkg.instantiate()`, and
  `setup --instantiate` on remotes (after `--clone` or `--rsync`), or
  `go --rsync` / `drive --rsync` onto an empty/missing path.
- A `[workspace]` member keeps its own `Project.toml` as `--project`.
  `setup --rsync` sends the directory that holds the Manifest Pkg reads,
  which may be a parent of the member. Worker `--project` stays the member,
  and `go` runs in that directory. `setup --clone` places the git work tree
  so that Manifest directory is the deploy root. A lock outside that tree,
  including a symlink to one, fails before instantiate. A `[sources]`
  `path` outside that tree fails the same way. An absolute path fails
  even when it sits inside the tree: the file is copied unchanged, and
  the worker resolves it on its own filesystem. A relative path whose
  directory entry is an absolute symlink fails the same way, because
  rsync keeps that link text. Clone and git sync also
  fail when that path is not in the commit they send, including an
  untracked or ignored directory. A symlink in that commit whose target
  is absolute, or leaves the work tree, fails even when the working-tree
  link looks local. A `url` source is fetched
  on the worker. No Manifest still means instantiate resolves, as before.
- Do not `Pkg.develop` DistSSHKit (or a `[sources]` path) in a job project
  you copy to workers. The Manifest records an absolute path the workers
  do not have. `Pkg.add` from General for real runs; keep a separate env
  to develop DistSSHKit.

Demo scripts live under `./distsshkit_demos/` after `demo install
with_kit` (or `without_kit`); see
[Home](@ref DistSSHKit.jl).

## Checks

The `ssh …` snippets below are **examples** you can type yourself — DistSSHKit
does not run them. `USER@HOST` is a placeholder (`user@hostname`, an IP, or an
SSH config `Host` alias). Timeouts and extra `-o` flags need not match
this machine (`ConnectTimeout` here is `5`; SSH from this machine uses `10` plus keepalives).

- Local-only first run: the **This machine** list is enough.
- Using remotes: add **Each SSH host** too. For the probe, use
  `setup --check` at the end of that subsection.

### This machine

- `julia --version`
- `uname -s` — Darwin or Linux
- `which ssh` — remotes
- `which rsync` — remotes / collect
- `which git` — git deploy path only

`setup --check` prints the same three on this machine (`ssh` missing
fails the check; `rsync` / `git` warn). Spawn uses those messages instead
of a raw `ENOENT`.

### Each SSH host

Example — passwordless login (once per host):

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new USER@HOST echo ok
```

Example — Julia **1.13+**, same major.minor as this machine. Non-interactive
`ssh` often has no login `PATH`, so the binary must be at a **full path**
below (or you pass `--julia` / `JULIA_DISTRIBUTED_EXE`):

- `$HOME/.juliaup/bin/julia`
- macOS: `/opt/homebrew/bin/julia`, `/usr/local/bin/julia`, `/usr/bin/julia`
- Linux / WSL2: `/usr/bin/julia`, `/usr/local/bin/julia`

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new \
  USER@HOST '$HOME/.juliaup/bin/julia --version'
```

If the major.minor does not match this machine, align with juliaup
(changes that host's **default** Julia):

```bash
julia --project=. -m DistSSHKit up child:USER@HOST
julia --project=. -m DistSSHKit up parent   # this machine
julia --project=. -m DistSSHKit up update child:USER@HOST
# or manually (official install or macOS Homebrew):
# ssh USER@HOST '$HOME/.juliaup/bin/juliaup add 1.13 &&
#   $HOME/.juliaup/bin/juliaup update 1.13 &&
#   $HOME/.juliaup/bin/juliaup default 1.13'
# ssh USER@HOST '/opt/homebrew/bin/juliaup add 1.13 &&
#   /opt/homebrew/bin/juliaup update 1.13 &&
#   /opt/homebrew/bin/juliaup default 1.13'
```

Use this machine's major.minor in place of `1.13`. If juliaup is not
installed on the host, install it first
([juliaup](https://github.com/JuliaLang/juliaup) or `brew install juliaup`);
DistSSHKit does not bootstrap juliaup.

If Julia is at another path above, put that path in the command instead.

The kit covers the same ground (`ssh`, Julia path / version, remote project)
with `setup --check` (this **is** a DistSSHKit command):

```bash
julia --project=. -m DistSSHKit setup --check child:USER@HOST
```

`setup --check` prints an `up` Fix when Julia is missing or the
major.minor differs.

Example — `git` only if that host will clone / pull:

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new USER@HOST 'which git'
```

## Queue host and client

A **queue host** is the always-on macOS or Linux machine that holds
`~/.distsshqueue` and runs `serve`. WSL2 is a client or a worker, not
this role. A client submits, watches, fetches, or cancels. The run
starts on the queue host, not on the client.

The queue host needs passwordless **`ssh`** to each worker, plus
**`rsync`**. **`git`** is only for a git deploy. A client also needs
**`ssh`** and **`rsync`**: `qhost:` submit copies the job tree to the
queue host, and `fetch` copies the finished leaf back. The client's
Julia major.minor does not have to match the queue host. Workers must
match the queue host (`setup --check`; patch-only differences warn).
A mismatch between this process and the queue host's DistSSHQueue
prints a `!` note on stderr (`DISTSSHKIT_QUIET` hides it).

Anyone who can `submit` as the queue-host user can run arbitrary Julia
as that user, and the run then uses passwordless SSH to every listed
worker. That is one trust domain: shared shell access, not a place for
untrusted submitters. See the trust note under [Remotes](@ref) above.

After `qhost up` changes the queue host's default Julia, stop `serve`
and start it again. If `enable` is in use, run `enable` again so the
OS unit picks up the new path, then restart `serve`. A job that is
already running keeps its old binary.

## [Where files live](@id where-files-live)

`qhost:` is an SSH name, not a storage prefix. The queue's table and
the run's result dirs accumulate on the queue host. `qhost:` submit
rsyncs the client job tree to `~/.distsshqueue/stage/<uuid>`. The run
still copies that tree to workers. `teardown` removes
`~/.distsshqueue` (including `stage/`). It does not remove a git clone
or `.distsshkit/` outside that directory. Ownership is in
[Artifacts and paths](@ref Queue-artifacts).

`parent` runs `stage/<uuid>/` in place. Leave
`DISTRIBUTED_REMOTE_PROJECT_ROOT` unset in shared `config.toml` so each
`child:` copy stays `~/stage/<uuid>`.

### Client tree

No `~/.distsshqueue` on the client. The job env only needs the queue
commands loadable.

```text
~/my-job/
  Project.toml          DistSSHKit or DistSSHQueue
  Manifest.toml
  SCRIPT.jl             rsync'd on qhost: submit
  .distsshqueue/tickets/<uuid>           after each qhost: submit
  .distsshqueue/<kind>/<stem>_<id8>/     after fetch
    .distsshqueue-fetch-id
    ...                                  primary artifact copy
```

### Queue-host tree

```text
~/.distsshqueue/
  config.toml
  jobs.toml             every row (no prune)
  jobs.toml.log
  jobs.toml.pid         while serve is up
  jobs.toml.stopped     after stop, until serve
  env/                  qhost: default --project=; enable if present
  stage/<uuid>/         client tree after each qhost: submit
    Project.toml
    SCRIPT.jl
    .distsshkit/runs/<kind>/<run>/       run.toml, kit.pid, kit.result
    .distsshkit/<kind>/SCRIPT_<UTC>_<id>/  the run or the script picks it
    .distsshkit/setup/*.log
```

`enable` writes a user unit (no root). `disable` removes that file.
The table and the run's dirs stay.

- **macOS** — `~/Library/LaunchAgents/org.distsshqueue.serve.plist`
- **Linux / WSL2** — `~/.config/systemd/user/distsshqueue.serve.service`

### Worker tree

`parent` is the queue host. It runs the stage tree in place, and the
queue's table stays next to it. A `child:` host has no queue table.
The run rsyncs the job project there and instantiates it before the
run. Artifacts do not stay on the worker: the run collects them back
to the queue host.

```text
~/stage/<uuid>/         child: copy after qhost: submit (this uuid only)
  Project.toml
  Manifest.toml
  SCRIPT.jl
```

Next: [Home](@ref DistSSHKit.jl) · [Prepare](@ref Tutorial-Prepare).
