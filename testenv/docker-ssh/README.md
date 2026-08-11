# Docker SSH workers (CI E2E)

Real OpenSSH + rsync Linux workers. CI remote SSH coverage uses this stack
([`SSH E2E`](../../.github/workflows/ssh-e2e.yml)). Optional Mac-only path:
[`../apple-container-ssh`](../apple-container-ssh) (Apple `container`, same image;
**not CI**).

## Coverage matrix

| Controller | Worker | What CI asserts |
| --- | --- | --- |
| Linux (`ubuntu-latest`) | Linux ×2 (this compose) | Same suite: controller Julia resolve + remote `julia=auto` (path + major.minor) + setup/drive/go/API |
| macOS (`macos-15-intel` + Colima) | Linux ×2 (same image) | **Same suite** as linux-to-linux. Controller path resolve runs on Darwin; remote detect still targets Linux workers |
| Either | `local:N` | Mixed smoke inside the same job |

### Honest limits

- Remote Julia detection is exercised on **Linux workers only** (both matrix jobs).
- **Not covered (no free CI):** Linux controller → macOS worker; Mac workers (use apple-container locally).
- **Git parity (`--require-git`):** covered in SSH E2E via a separate git remote
  root (`clone` from a bare on worker-1 → `--sync` → `drive --require-git`).
  The rsync path still excludes `.git/` and does not claim parity.

Worker image pins Julia **1.12** (juliaup `--default-channel 1.12`) to match CI controllers so `--check` can run **without** `--ignore-julia-version`.

Ports are published on `127.0.0.1` (not the Colima VM IP) so macOS 15 Local
Network Privacy does not block SSH from the controller.

## Layout

| Path | Role |
| --- | --- |
| [`Dockerfile`](Dockerfile) / [`start.sh`](start.sh) | Worker image (sshd, rsync, git, Julia 1.12 via juliaup) |
| [`compose.yml`](compose.yml) | Two workers (`worker-1` / `worker-2`) |
| [`scripts/gen-keys.sh`](scripts/gen-keys.sh) | Controller + inter-worker keys, SSH config |
| [`scripts/up.sh`](scripts/up.sh) | Keys → compose up → wait (`--e2e` also runs the suite) |
| [`scripts/wait-ready.sh`](scripts/wait-ready.sh) | BatchMode SSH + Julia probe |
| [`scripts/down.sh`](scripts/down.sh) | Compose down |
| [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh) | CI macOS Intel: Lima/Colima/Docker with download retries |
| `.generated/` | gitignored SSH config / keys (created by scripts) |

SSH Host aliases (written to `.generated/ssh_config`):

- `distsshkit-w1` → `127.0.0.1:2222` user `dev`
- `distsshkit-w2` → `127.0.0.1:2223` user `dev`

## Local use (optional)

Requires Docker Compose:

```bash
./scripts/up.sh --e2e    # workers + suite (always from kit root)
./scripts/up.sh          # workers only
./scripts/down.sh
```

Suite coverage / artifacts: see `test/integration/ssh/run.jl` and
`test/artifacts/README.md` (`$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt`,
plus `JULIA_PATHS.txt`).

Manual smoke:

```bash
./scripts/up.sh
ssh -F .generated/ssh_config distsshkit-w1 'echo ok; julia --version'
```

## CI

[`.github/workflows/ssh-e2e.yml`](../../.github/workflows/ssh-e2e.yml) runs
`./scripts/up.sh --e2e` on both `linux-to-linux` and `macos-to-linux`.
On `macos-15-intel`, Docker is installed via
[`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh).

Usual `Pkg.test()` does **not** start Docker and does **not** run this suite.
