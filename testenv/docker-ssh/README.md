# Docker SSH workers (CI E2E)

Real OpenSSH + rsync Linux workers. CI remote SSH coverage uses this stack
([`SSH E2E`](../../.github/workflows/ssh-e2e.yml)). Optional Mac-only path:
[`../apple-container-ssh`](../apple-container-ssh) (Apple `container`, same image;
**not CI**).

## Coverage matrix

| Controller | Worker | Where |
| --- | --- | --- |
| Linux (`ubuntu-latest`) | Linux ×2 (this compose) | **CI** — full suite (path resolve, rsync, git clone/sync/`--require-git`, drive/go/API) |
| macOS (Docker Desktop / Colima) | Linux ×2 (same image) | **Local only** — same `./scripts/up.sh --e2e` (exercises Darwin controller Julia resolve) |
| Either | `local:N` | Mixed smoke inside the same suite |

### Honest limits

- CI does **not** run a macOS controller job (Colima on `macos-15-intel` was too slow for PRs).
- Remote Julia detection is exercised on **Linux workers**.
- **Not covered (no free CI):** Linux controller → macOS worker; Mac workers (use apple-container locally).
- **Git parity (`--require-git`):** covered in the suite via a separate git remote root
  (`clone` from a bare on worker-1 → `--sync` → `drive --require-git`).
  The rsync path still excludes `.git/` and does not claim parity.

Worker image pins Julia **1.12** (juliaup `--default-channel 1.12`) to match CI controllers so `--check` can run **without** `--ignore-julia-version`.

On macOS, publish ports on `127.0.0.1` (Docker Desktop / Colima defaults) so macOS 15 Local
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
| [`scripts/setup-colima-ci.sh`](scripts/setup-colima-ci.sh) | Optional: Colima on Intel Mac CI (not used by default workflow) |
| `.generated/` | gitignored SSH config / keys (created by scripts) |

SSH Host aliases (written to `.generated/ssh_config`):

- `distsshkit-w1` → `127.0.0.1:2222` user `dev`
- `distsshkit-w2` → `127.0.0.1:2223` user `dev`

## Local use (macOS or Linux)

Requires Docker Compose (Docker Desktop on Mac is fine):

```bash
./scripts/up.sh --e2e    # workers + suite (always from kit root)
./scripts/up.sh          # workers only
./scripts/down.sh
```

On a Mac this is how you cover **Darwin controller** path resolve against Linux workers.
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
`./scripts/up.sh --e2e` on `ubuntu-latest` only (`linux-to-linux`).

Usual `Pkg.test()` does **not** start Docker and does **not** run this suite.
