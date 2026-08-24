# Tests

How this repo tests DistSSHKit. Maintainer checklist: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the kit checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl` (unit + integration), sequential `@testset`s, `test/Project.toml`. Aqua is a separate CI job, not `Pkg.test()`.

Real SSH:

```bash
testenv/docker-ssh/scripts/up.sh --e2e
```

Details: [`testenv/docker-ssh/README.md`](../testenv/docker-ssh/README.md). Inventory: [SSH E2E](#ssh-e2e) below.

## Layout

```text
test/
  runtests.jl     # Pkg.test() — unit + integration
  e2e.jl          # real OpenSSH; not Pkg.test()
  support.jl      # loads support/
  support/        # subprocess, staging, E2E helpers
  unit/           # in-process (no child julia, no addprocs)
  integration/    # child julia and/or local addprocs
  fixtures/       # small scripts copied into temp hosts
  Project.toml
```

`unit/` mirrors `src/`:

```text
unit/
  DistSSHKit/     # ↔ src/DistSSHKit/ (API, setup cores, argv)
    argv/         # ↔ DistSSHKit/argv/
    setup/        # ↔ DistSSHKit/setup/
  cli/            # ↔ src/cli/
    drive/, go/, setup/, size/
```

`integration/` is grouped by area (`drive/`, `demos/`, `setup/`, `go/`, `size/`).

## Layers

Green on one layer does not imply the others. `Pkg.test()` does not run `e2e.jl`. Most of `Pkg.test()` wall time is integration. Child CLI uses `julia -m DistSSHKit`.

| Layer | Proves | Not | Time |
| --- | --- | --- | --- |
| JETLS | types / hints on entry files | runtime | ~25 s |
| Aqua | ambiguities, exports, compat (latest registry Aqua) | CLI / workers | ~5 s |
| unit | parse, paths, fake setup, throws | child julia, `addprocs`, SSH | ~45 s |
| integration | child CLI and/or **local** `addprocs` | real SSH / rsync | ~3 min |
| e2e | real SSH + rsync, two Linux workers; every PR (Compose) | local-only CLI wiring | ~15–25 min |
| e2e daily | same `e2e.jl` from Linux, macOS Intel, or WSL2 (not a PR check; required after a `cut` merge before register) | macOS workers | 10–50 min |
| doctests | `src/` docstring examples (Documenter, Julia 1.12) | workers / SSH | ~5 s |

## SSH E2E

Two Linux workers. `DISTSSHKIT_SSH_E2E=1`. Controller OS matrix: [`testenv/docker-ssh/README.md`](../testenv/docker-ssh/README.md). Apple silicon without Compose: [`testenv/apple-container-ssh/README.md`](../testenv/apple-container-ssh/README.md) (`./scripts/up.sh --e2e`).

Open logs with [`test/artifacts/README.md`](artifacts/README.md):

```bash
open "$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt"
rm -rf test/artifacts/ssh-e2e
```

Coverage uploads on **main push** (`Pkg.test` max) and **E2E daily** / **`cut` PR**
E2E (`DISTSSHKIT_CODE_COVERAGE=1` on `up.sh --e2e`). Ordinary PR E2E has no
coverage. Local:

```bash
DISTSSHKIT_CODE_COVERAGE=1 testenv/docker-ssh/scripts/up.sh --e2e
```

### Setup (rsync tree)

| Check | Fact |
| --- | --- |
| Julia resolve | controller and remotes share major.minor |
| `run_on_host` | `--version` exit 0; `-e exit(3)` is `.exitcode == 3` (no throw) |
| `--delete` | remote `Project.toml` is gone |
| `--rsync` | remote `Project.toml` exists |
| `--instantiate` / `--check` | job deps; Julia version (no `--ignore-julia-version`) |
| `--runtest` | job `Pkg.test` pass; a planted failure is non-zero |
| `--rsync` nonempty | refused |
| `~/…` remote path | delete → rsync → instantiate → drive still run |

### Drive / go / size

`square_file` writes the CSV in `main()` on the **controller**. Workers only return numbers. Collect tests use files workers write.

| Check | Fact |
| --- | --- |
| `size` | both hosts, `GB`, `Total:` |
| `square_echo` | remote compute; stdout has `param^2:` |
| `square_file` | local CSV exists; absent on the remote |
| `worker_*.txt` | on the worker; `run_on_host` read; `--collect-missing` restores; skip keeps junk; `--collect-overwrite` replaces; `kit.result` `hosts` names both remotes |
| `kit.progress` | `kit_progress_latest` last event is `done` after demo drive / go |
| worker `error(...)` | non-zero |
| mixed `parenthost:1` + two remotes | smoke `nw=3` |
| in-process `drive!` twice (reentrant) | each call `nw=2`; no worker leak (#144) |
| detached drive SIGKILL | wait until heartbeat monitors start, then remote `--worker` gone (#148) |
| `go pi_echo` | π on both hosts |
| `go pi_file` | slot `pi_results.txt` after go collect |
| `go --output-dir` | `pi_results.txt` under the given batch root |
| API | `setup!` / `go!(output_dir=)` / `pipeline!(collect=true)` on worker files |

### Git (separate remote root)

| Check | Fact |
| --- | --- |
| `--clone` / `--instantiate` / `--check` | remote hash matches |
| `--require-git` after a local bump | fails |
| `--sync` then `--require-git` | pass |
| `--pull` after controller `git push` | `e2e_sync_marker.txt` on the workers matches |

Worker-1 can SSH to worker-2 (compose DNS).

Not this file: macOS workers, dead hosts, fake `ssh`/`rsync`, local `with_kit` recipes (`test/integration/demos/`).

## Fakes vs real SSH

| Command | Core work | `Pkg.test()` | Bytes on a real remote |
| --- | --- | --- | --- |
| setup | `ssh` / `rsync` | fixtures `DISTSSHKIT_TEST_SSH` / `_RSYNC` | e2e |
| drive / go | `Distributed` workers | real **local** `addprocs` (no SSH fake) | e2e |
| drive collect | `ssh` / `rsync` of result trees | same fakes, **control flow only** (fake rsync does not copy) | e2e |
| size | plan math (+ optional RSS) | unit + local probe in `integration/size/` | e2e if needed |

Do not fake Julia SSH worker launch. Local workers stand in for drive/go; they cannot stand in for setup. `_run_kit_setup` / `_run_kit_go` use an ephemeral project unless `project_root` is set (E2E uses `test/artifacts/ssh-e2e/`).

## Writing tests

1. Add under `unit/` (src mirror) or `integration/<area>/`.
2. Top-level `include` in `runtests.jl` (JETLS follows that). Do not register `e2e.jl` there (`Pkg.test` must not SSH). `e2e.jl` is its own JETLS entry in `.github/jetls-check.sh`.
3. Subprocess helpers in `support/`; one-off scripts in `fixtures/`.
4. Short Oracle / non-guarantee comment at the top of the file.
5. Pin verbosity with `with_kit_verbosity` if you assert kit detail lines. `Pkg.test` defaults to `:progress`. `kit_confirm` and consent warnings must show in `:quiet`, `:progress`, and `:verbose`.

Helpers (via `support.jl`): `_child_julia_env`, `_run_kit_drive` / `_run_kit_setup` / `_run_kit_go` / `_run_kit_size`, `_mktemp_host` / `_with_tempdir` / `_stage_with_kit_demos!`, `_with_ssh_e2e_suite`, `_capture_stdio` / `with_kit_verbosity`.

| Variable | Default | Effect |
| --- | --- | --- |
| `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL` | `1` in test children | skip remote / `setup --cleanup` `pkill`; each child `rmprocs`es its own local workers |
| `DISTSSHKIT_SSH_E2E` | unset | `1` runs `test/e2e.jl` (needs docker-ssh workers) |
| `DISTSSHKIT_CODE_COVERAGE` | unset | `1` with `up.sh --e2e` → `--code-coverage=user` |

CLI also honors `DISTSSHKIT_QUIET`, `DISTSSHKIT_PROGRESS`, `DISTSSHKIT_VERBOSE`, `DISTSSHKIT_YES`, `DISTSSHKIT_HOSTS`, `DISTSSHKIT_HOSTS_FILE` (`src/DistSSHKit/argv/session.jl`).

## Aqua

CI and [`.github/aqua-check.sh`](../.github/aqua-check.sh) `Pkg.add("Aqua")` with no version pin. `Pkg` is a module dep (`using Pkg` in `src/DistSSHKit.jl`) so Aqua `stale_deps` can run.
