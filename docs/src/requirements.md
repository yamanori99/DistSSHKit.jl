# Requirements

Prerequisites for [Introduction](@ref DistSSHKit.jl) and
[Prepare](@ref Tutorial-Prepare). You can start local-only; add the remote
pieces when you SSH to other hosts. `pkg> add DistSSHKit` does not install
**`ssh`**, **`rsync`**, or **`git`**.

## All machines

Applies to the machine where you run the kit **and** each SSH host that runs
jobs.

- **macOS, Linux, and WSL2 Ubuntu** (not native Windows)
- **Julia 1.12+**
  - Library (`Pkg.add` / `using` / `go!` / `drive!`), CLI
    (`julia -m DistSSHKit`), and optional `distsshkit`
    ([User Guide](@ref Manual-distsshkit))
  - Same **major.minor** on the controller and SSH hosts (`setup --check`
    fails on a mismatch unless `--ignore-julia-version`; patch-only
    differences warn)
  - Prefer **[juliaup](https://github.com/JuliaLang/juliaup)**
    (`$HOME/.juliaup/bin/julia`): E2E workers and remote auto-detect start
    there. `--julia` / `JULIA_DISTRIBUTED_EXE` override. Missing path or a
    related bug: [open an Issue](https://github.com/yamanori99/DistSSHKit.jl/issues).

WSL2 is Linux. Run the kit **inside** the distro (not PowerShell). Keep the
project on the Linux filesystem (`~/…`), not `/mnt/c/…`. Install `ssh` /
`rsync` / Julia in WSL. SSH E2E: same `./testenv/docker-ssh/scripts/up.sh --e2e`
as Linux (Docker Compose must be visible from WSL).

## Remotes

No hard limit on the number of remote hosts — more hosts just means more time
spent on SSH connections and deployment, so start with a few and scale up.
If SSH disconnects are a risk, use machines that stay up and keep the master's
run alive with something like `tmux`.

When you use SSH hosts (not just `local:N`):

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
  `setup --instantiate` on remotes (after `--clone` or `--rsync`).

Demo scripts live under `./demos/` after `demo install with_kit` (or
`without_kit`); see
[Introduction](@ref DistSSHKit.jl).

## Checks

The `ssh …` snippets below are **examples** you can type yourself. DistSSHKit
does not run them. `USER@HOST` is a placeholder (`user@hostname`, an IP, or an
SSH config `Host` alias). Timeouts and extra `-o` flags need not match the
kit (`ConnectTimeout` here is `5`; the kit uses `10` plus keepalives).

Local-only first run: the **Where you run the kit** list is enough. Add
**Each SSH host** when you use remotes. For the kit's own probe, use
`setup --check` at the end of that subsection.

### Where you run the kit

- `julia --version`
- `uname -s` — Darwin or Linux
- `which rsync` — remotes / collect
- `which git` — git deploy path only

### Each SSH host

Example — passwordless login (once per host):

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new USER@HOST echo ok
```

Example — Julia **1.12+** (same major.minor as the kit machine, via juliaup).
Log in, find the binary, then check with that **full path** (non-interactive
`ssh` often has no login `PATH`, so bare `julia` fails):

- `ssh USER@HOST`
- `which julia` (often `$HOME/.juliaup/bin/julia`)
- `exit`

Replace `/path/from/which/julia` with that path:

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new USER@HOST '/path/from/which/julia --version'
```

The kit covers the same ground (`ssh`, Julia path / version, remote project)
with `setup --check` (probes common Julia locations; this **is** a DistSSHKit
command):

```bash
julia --project=. -m DistSSHKit setup --check USER@HOST
```

Example — `git` only if that host will clone / pull:

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new USER@HOST 'which git'
```

Next: [Introduction](@ref DistSSHKit.jl) · [Prepare](@ref Tutorial-Prepare).
