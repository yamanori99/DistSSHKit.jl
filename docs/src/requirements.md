# Requirements

Prerequisites for [Introduction](@ref DistSSHKit.jl) and
[First Steps](@ref Tutorial-Prepare). You can start local-only; add the remote
pieces when you SSH to other hosts.

## All machines

Applies to the machine where you run `julia -m DistSSHKit` **and** each SSH
host that runs jobs.

- **macOS and Linux**
- **Julia** — library (`Pkg.add` / `using` / `go!` / `drive!`): **1.10+**. CLI
  (`julia -m DistSSHKit`), tests, and docs: **1.12+**. `@main` / compile entry:
  **1.12+** (no such entry on 1.10). Prefer the same **major.minor** on SSH hosts
  (`setup --check` fails on a major.minor mismatch unless you pass
  `--ignore-julia-version`; patch-only differences warn). On SSH hosts, path is
  auto-detected, or set `--julia` / `JULIA_DISTRIBUTED_EXE`.

When you run the kit with `-m`, treat every machine as **1.12+**. API-only on
1.10: still match major.minor between controller and SSH hosts.

## Remotes

When you use SSH hosts (not just `local:N`):

**Where you run `julia -m DistSSHKit`** — also install:

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
  nearest `Project.toml` above each script).
- Declare dependencies in that `Project.toml` / `Manifest.toml`. Install them on
  **every** machine that runs jobs: local `Pkg.instantiate()`, and
  `setup --instantiate` on remotes (after `--clone` or `--rsync`).

Demo scripts live under `./demos/` after `demo install`; see
[Introduction](@ref DistSSHKit.jl).

## Checks

Example commands only — DistSSHKit does not run them. Local-only first run: the
blocks under **Where you run the kit** are enough. Add the **Each SSH host**
blocks when you use remotes.

In SSH examples, replace `USER@HOST` with `user@hostname`, an IP, or an SSH
config `Host` alias — not the literal string `USER@HOST`.

### Where you run the kit

```bash
julia --version
uname -s          # Darwin or Linux
which rsync       # remotes / collect
which git         # git deploy path only
```

### Each SSH host

Passwordless login (once per host):

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new USER@HOST echo ok
```

Julia (prefer the same major.minor as the kit machine). Log in, find the binary,
then check with that **full path** (non-interactive `ssh` often has no login
`PATH`, so bare `julia` fails):

```bash
ssh USER@HOST
which julia
exit
```

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new USER@HOST '/path/from/which/julia --version'
```

The same checks (SSH, Julia path / version, remote project) are also covered by
`setup --check`, which probes common Julia locations for you:

```bash
julia --project=. -m DistSSHKit setup --check USER@HOST
```

`git` only if that host will clone / pull:

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new USER@HOST 'which git'
```

Next: [Introduction](@ref DistSSHKit.jl) · [Prepare](@ref Tutorial-Prepare).
