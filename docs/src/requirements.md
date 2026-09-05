# Requirements

Prerequisites for [Introduction](@ref DistSSHKit.jl) and
[Prepare](@ref Tutorial-Prepare). You can start local-only; add the remote
pieces when you SSH to other hosts. `pkg> add DistSSHKit` does not install
**`ssh`**, **`rsync`**, or **`git`**.

Runs need **SSH between machines** (LAN or VPN is enough). Constant
internet is not required; you mainly need it for `Pkg.add` /
`instantiate`, outbound `git clone` / `git pull`, or installing Julia.

## All machines

Applies to the machine where you run the kit **and** each SSH host that runs
jobs.

- **macOS, Linux, and WSL2 Ubuntu** (not native Windows)
- **Julia 1.12+**
  - Library (`Pkg.add` / `using` / `go!` / `drive!`), CLI
    (`julia -m DistSSHKit`), and optional `distsshkit`
    ([User Guide](@ref Manual-distsshkit))
  - Same **major.minor** on the kit parent and SSH hosts (`setup --check`
    fails on a mismatch unless `--ignore-julia-version`; patch-only
    differences warn)
  - Prefer **[juliaup](https://github.com/JuliaLang/juliaup)** so
    `$HOME/.juliaup/bin/julia` is available (or macOS Homebrew
    `/opt/homebrew/bin/julia` / `/usr/local/bin/julia`). Otherwise put a
    1.12+ binary at a usual OS path ([Checks](@ref)) or set `--julia` /
    `JULIA_DISTRIBUTED_EXE`. On major.minor mismatch, use
    [`setup --juliaup`](@ref Manual-setup) when juliaup is already on the
    host (official install or Homebrew; see [Checks](@ref)). Missing path
    or a related bug:
    [open an Issue](https://github.com/yamanori99/DistSSHKit.jl/issues).

WSL2 is Linux, with a few extra rules:

- Run the kit **inside** the distro, not PowerShell
- Keep the project on the Linux filesystem (`~/…`), not `/mnt/c/…`
- Install `ssh` / `rsync` / Julia inside WSL
- SSH E2E uses the same `./testenv/docker-ssh/scripts/up.sh --e2e` as Linux
  (Docker Compose must be visible from WSL)

## Remotes

No hard limit on remote hosts. More remotes means more SSH and deploy time —
start with a few.

DistSSHKit runs one job while you stay connected.
[DistSSHQueue.jl](https://yamanori99.github.io/DistSSHQueue.jl/stable/)
(`pkg> add DistSSHQueue`) queues jobs on a machine that stays on.
DistSSHKit still does the running. `tmux` keeps an already-running job;
it does not queue later ones.

When you use SSH hosts (not just `parent:N`):

Passwordless SSH means the kit parent and those hosts are **one trust
domain**: whoever can run the kit as you, can run arbitrary Julia on each
listed host as that remote user. That is the intended lab premise (shared
shell access). With
[DistSSHQueue.jl](https://yamanori99.github.io/DistSSHQueue.jl/stable/),
the queue host widens who can trigger those runs.

**Where you run the kit** — also install:

- **`ssh`** — passwordless login to each host
- **`rsync`** — collect results (`go` / `drive`); push the project tree only
  without git (`setup --rsync`)
- **`git`** — git deploy path only (clone / push / pull); skip for rsync-only

**Each SSH host:**

- **Passwordless SSH** from the machine where you run the kit (repeat per host;
  use a connect timeout — bare `ssh` can hang on a bad IP). See [Checks](@ref)
  below.
- **`git`** — git deploy path only (clone / pull on the host); skip for
  rsync-only. Git vs rsync: [First Steps · Prepare](@ref Tutorial-Prepare),
  [User Guide · setup](@ref Manual-setup).

## Project

DistSSHKit assumes a Julia **project** — `Project.toml` at the project root
(not a subfolder like `demos/`):

- Run with `julia --project=.` from that directory (the kit activates the
  nearest `Project.toml` above each script). `julia -m DistSSHKit` from a
  project that only *depends on* DistSSHKit uses that job's `Project.toml`,
  not the kit's (`DISTRIBUTED_PROJECT_ROOT` overrides).
- Declare dependencies in that `Project.toml` / `Manifest.toml`. Install them on
  **every** machine that runs jobs: local `Pkg.instantiate()`, and
  `setup --instantiate` on remotes (after `--clone` or `--rsync`), or
  `go --rsync` / `drive --rsync` onto an empty/missing path.

Demo scripts live under `./distsshkit_demos/` after `demo install
with_kit` (or `without_kit`); see
[Introduction](@ref DistSSHKit.jl).

## Checks

The `ssh …` snippets below are **examples** you can type yourself — DistSSHKit
does not run them. `USER@HOST` is a placeholder (`user@hostname`, an IP, or an
SSH config `Host` alias). Timeouts and extra `-o` flags need not match the
kit (`ConnectTimeout` here is `5`; the kit uses `10` plus keepalives).

- Local-only first run: the **Where you run the kit** list is enough.
- Using remotes: add **Each SSH host** too. For the kit's own probe, use
  `setup --check` at the end of that subsection.

### Where you run the kit

- `julia --version`
- `uname -s` — Darwin or Linux
- `which ssh` — remotes
- `which rsync` — remotes / collect
- `which git` — git deploy path only

`setup --check` prints the same three on the kit parent (`ssh` missing
fails the check; `rsync` / `git` warn). Spawn uses those messages instead
of a raw `ENOENT`.

### Each SSH host

Example — passwordless login (once per host):

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new USER@HOST echo ok
```

Example — Julia **1.12+**, same major.minor as the kit machine. Non-interactive
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

If the major.minor does not match the kit machine, align with juliaup
(changes that host's **default** Julia):

```bash
julia --project=. -m DistSSHKit setup --juliaup child:USER@HOST
julia --project=. -m DistSSHKit setup --juliaup parent   # this machine
# or manually (official install or macOS Homebrew):
# ssh USER@HOST '$HOME/.juliaup/bin/juliaup add 1.12 &&
#   $HOME/.juliaup/bin/juliaup update 1.12 &&
#   $HOME/.juliaup/bin/juliaup default 1.12'
# ssh USER@HOST '/opt/homebrew/bin/juliaup add 1.12 &&
#   /opt/homebrew/bin/juliaup update 1.12 &&
#   /opt/homebrew/bin/juliaup default 1.12'
```

Use your kit parent's major.minor in place of `1.12`. If juliaup is not
installed on the host, install it first
([juliaup](https://github.com/JuliaLang/juliaup) or `brew install juliaup`);
DistSSHKit does not bootstrap juliaup.

If Julia is at another path above, put that path in the command instead.

The kit covers the same ground (`ssh`, Julia path / version, remote project)
with `setup --check` (this **is** a DistSSHKit command):

```bash
julia --project=. -m DistSSHKit setup --check child:USER@HOST
```

`setup --check` prints a `--juliaup` Fix when Julia is missing or the
major.minor differs.

Example — `git` only if that host will clone / pull:

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes \
  -o StrictHostKeyChecking=accept-new USER@HOST 'which git'
```

Next: [Introduction](@ref DistSSHKit.jl) · [Prepare](@ref Tutorial-Prepare).
