# Docker SSH workers (CI E2E)

Real OpenSSH + rsync Linux workers. CI remote SSH coverage uses this stack
([`SSH E2E`](../../.github/workflows/CI.yml)). Optional Mac-only path
(same image and `test/e2e.jl`):
[`../apple-container-ssh`](../apple-container-ssh) — `./scripts/up.sh --e2e`
(Apple `container`; **not CI**). Do not run both stacks at once (shared
`ssh_config`).

## Coverage matrix

- Linux (`ubuntu-latest`), workers `ubuntu:24.04` ×2: **CI** — PR / main
  (`E2E`) and weekly (`E2E weekly / ubuntu-latest → ubuntu-24.04`)
- macOS Intel (`macos-15-intel` + Colima), same image: **E2E weekly** —
  `E2E weekly / macos-15-intel → ubuntu-24.04`
- WSL2 (`windows-latest`), same image: **E2E weekly** —
  `E2E weekly / windows-latest (WSL2) → ubuntu-24.04`
- Either controller, `parent:N`: mixed smoke inside the same suite

Suite inventory: [`test/README.md`](../../test/README.md#ssh-e2e).

### Honest limits

- CI macOS controller is **weekly / dispatch** (`macos-15-intel` +
  Colima). Apple Silicon GitHub runners cannot nest VMs.
- Remote Julia detection is exercised on **Linux workers**.
- **Not covered (no free CI):** Linux controller → macOS worker; Mac workers
  (local: [`apple-container-ssh`](../apple-container-ssh/README.md)
  `./scripts/up.sh --e2e`).
- **Git parity (`--require-git`):** covered via a separate git remote root
  (`clone` from a bare on child-1 → `--sync` → `drive --require-git`).
  Mismatch before `--sync` must fail. `--pull` after a controller `git push`
  is checked by reading `e2e_sync_marker.txt` on the workers.
  The rsync path still excludes `.git/` and does not claim parity.

Worker image pins Julia to CI slot **max** (juliaup `--default-channel`,
today **1.13**)
so `--check` can run **without** `--ignore-julia-version`. Pins live in
[`.github/julia-slots.env`](../../.github/julia-slots.env). Install policy:
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/dev/requirements/).

On macOS, publish ports on `127.0.0.1` (Docker Desktop / Colima defaults)
so macOS 15 Local
Network Privacy does not block SSH from the controller.

## Layout

| Path | Role |
| --- | --- |
| [`Dockerfile`](Dockerfile) / [`start.sh`](start.sh) | Worker image |
| [`compose.yml`](compose.yml) | Two children (`child-1` / `child-2`) |
| [`scripts/gen-keys.sh`](scripts/gen-keys.sh) | Keys and SSH config |
| [`scripts/up.sh`](scripts/up.sh) | Keys → compose up → wait |
| [`scripts/wait-ready.sh`](scripts/wait-ready.sh) | SSH + Julia probe |
| [`scripts/down.sh`](scripts/down.sh) | Compose down |
| [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh) | Colima CI |
| `.generated/` | gitignored SSH config / keys (created by scripts) |

SSH Host aliases (written to `.generated/ssh_config`):

- `distsshkit-w1` → `127.0.0.1:2222` user `dev`
- `distsshkit-w2` → `127.0.0.1:2223` user `dev`

## Local use (macOS, Linux, or WSL2)

Requires Docker Compose (Docker Desktop on Mac is fine; on WSL2, Docker must be
visible from the distro). Keep a WSL tree under `~/…`, not `/mnt/c/…`.

```bash
./scripts/up.sh --e2e    # workers + suite (always from kit root)
./scripts/up.sh          # workers only
./scripts/down.sh
```

Skip the Julia-in-Docker build (macOS / WSL) by pulling the public image from
`main`'s last successful `E2E weekly`. If you changed `Dockerfile` /
`compose.yml`,
build locally instead (omit `DISTSSHKIT_WORKER_IMAGE`).

```bash
export DISTSSHKIT_WORKER_IMAGE=ghcr.io/yamanori99/\
distsshkit-linux-ssh-worker:latest
./scripts/up.sh --e2e
```

On a Mac or in WSL2 this is how you cover that controller against Linux workers.
Suite coverage / artifacts: see `test/e2e.jl` and
`test/artifacts/README.md` (`$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt`,
plus `JULIA_PATHS.txt`).

Manual smoke:

```bash
./scripts/up.sh
ssh -F .generated/ssh_config distsshkit-w1 'echo ok; julia --version'
```

## CI

[`.github/workflows/CI.yml`](../../.github/workflows/CI.yml) runs
`./scripts/up.sh --e2e` on `ubuntu-latest` when E2E-relevant paths change,
and for `cut` pull requests or manual dispatches
(`ubuntu-latest → ubuntu-24.04`).
[`.github/workflows/ssh-e2e-weekly.yml`][e2e-weekly]
(`E2E weekly`) runs Sunday 04:00 JST or via Run workflow: bake
`ubuntu-latest (image)` to GHCR, then `ubuntu-latest`, `macos-15-intel`, and
`windows-latest (WSL2)` pull that tag and run the suite. Weekly Linux is the
same suite as PR E2E, on the timer, not a PR check. After a `cut` merge,
dispatch it on that commit before `@JuliaRegistrator register`.

Those controller jobs wait for `ubuntu-latest (image)` then pull
`ghcr.io/<owner>/distsshkit-linux-ssh-worker:<sha>` instead of building
Julia-in-Docker on Colima / WSL `dockerd`. Push to GHCR is retried until the
tag is inspectable (GHCR `unknown blob`). After the weekly Linux suite,
`:latest`
is pushed for
local pull. The package is meant to be **public** (one-time: package Settings →
Change visibility). Local `./scripts/up.sh` still builds unless you set
`DISTSSHKIT_WORKER_IMAGE`. Colima on Intel runners uses `--cpu 3 --memory 8`
so the Darwin controller keeps RAM.

Usual `Pkg.test()` does **not** start Docker and does **not** run this suite.

[e2e-weekly]: ../../.github/workflows/ssh-e2e-weekly.yml
