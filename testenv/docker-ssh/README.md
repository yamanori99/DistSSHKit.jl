# Docker SSH workers (CI E2E)

Real OpenSSH + rsync Linux workers. CI remote SSH coverage uses this stack
([`SSH E2E`](../../.github/workflows/ssh-e2e.yml)). Optional Mac-only path:
[`../apple-container-ssh`](../apple-container-ssh) (Apple `container`, same image).

## Coverage matrix

| Controller | Worker | Where |
| --- | --- | --- |
| Linux | Linux (×2) | CI `ubuntu-latest` + this compose stack |
| macOS | Linux (×2) | CI `macos-15-intel` + Colima (`scripts/setup-colima-ci.sh`) + localhost ports 2222/2223 |
| macOS / Linux | local workers | Same E2E job (`local:2` smoke) |

**Not covered (no free CI path):** Linux controller → macOS worker.

Ports are published on `127.0.0.1` (not the Colima VM IP) so macOS 15 Local
Network Privacy does not block SSH from the controller.

## Layout

| Path | Role |
| --- | --- |
| [`Dockerfile`](Dockerfile) / [`start.sh`](start.sh) | Worker image (sshd, rsync, git, Julia via juliaup) |
| [`compose.yml`](compose.yml) | Two workers (`worker-1` / `worker-2`) |
| [`scripts/gen-keys.sh`](scripts/gen-keys.sh) | Controller + inter-worker keys, SSH config |
| [`scripts/up.sh`](scripts/up.sh) | Keys → compose up → wait |
| [`scripts/wait-ready.sh`](scripts/wait-ready.sh) | BatchMode SSH + Julia probe |
| [`scripts/down.sh`](scripts/down.sh) | Compose down |
| [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh) | CI macOS Intel: Lima/Colima/Docker with download retries |
| `.generated/` | gitignored SSH config / keys (created by scripts) |

SSH Host aliases (written to `.generated/ssh_config`):

- `distsshkit-w1` → `127.0.0.1:2222` user `dev`
- `distsshkit-w2` → `127.0.0.1:2223` user `dev`

## Local use (optional)

Requires Docker Compose.

```bash
cd testenv/docker-ssh
./scripts/up.sh

export DISTRIBUTED_SSH_OPTS="-F $(pwd)/.generated/ssh_config"
export DISTRIBUTED_REMOTE_PROJECT_ROOT=/home/dev/distsshkit-e2e
export DISTSSHKIT_YES=1

# From the DistSSHKit repo root:
DISTSSHKIT_SSH_E2E=1 julia --project=. test/integration/ssh/run.jl

# Suite covers (see test/integration/ssh/run.jl):
#   local with_kit square_echo / square_file
#   remote: setup delete/rsync/instantiate/check, size,
#           drive square_echo (2 remotes), drive mixed smoke,
#           go pi_echo + pi_file (both remotes + collect),
#           rsync refuse, inter-worker SSH
#
# Kept under (see test/artifacts/README.md):
#   $(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt

./scripts/down.sh
```

Manual smoke:

```bash
ssh -F .generated/ssh_config distsshkit-w1 'echo ok; julia --version'
```

## CI

[`.github/workflows/ssh-e2e.yml`](../../.github/workflows/ssh-e2e.yml) builds this
stack, then runs `test/integration/ssh/run.jl` with `DISTSSHKIT_SSH_E2E=1`.
On `macos-15-intel`, Docker is installed via
[`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh) (retrying Lima/Colima
downloads instead of piping `curl` into `tar`).

Usual `Pkg.test()` does **not** start Docker and does **not** run this suite.
