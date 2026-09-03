# Tests

How this repo tests DistSSHKit. Maintainer checklist:
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the kit checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl` (unit + integration), sequential `@testset`s,
`test/Project.toml`. Aqua is a separate CI job, not `Pkg.test()`.
`Pkg.test()` must pass on a Registry install (no kit `Manifest.toml`, often
mode 444): job smokes pass `-y`; real `ssh` / `git` spawn runs only when that
binary is on `PATH`; real SSH clusters stay in `e2e.jl`. Occasional copy
recipe: [Registry tree](#registry-tree).

Real SSH:

```bash
testenv/docker-ssh/scripts/up.sh --e2e
```

Details:
[`testenv/docker-ssh/README.md`](../testenv/docker-ssh/README.md).
Inventory: [SSH E2E](#ssh-e2e) below.

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

`integration/` is grouped by area (`drive/`, `demos/`, `setup/`, `go/`,
`size/`).

## Layers

Green on one layer does not imply the others. `Pkg.test()` does not run
`e2e.jl`. Most of `Pkg.test()` wall time is integration. Child CLI uses
`julia -m DistSSHKit`.

- **JETLS** (~25 s): types / hints on entry files. Not runtime.
- **Aqua** (~5 s): ambiguities, exports, compat (latest registry Aqua).
  Not CLI / workers.
- **unit** (~45 s): parse, paths, fake setup, throws. Not child julia,
  `addprocs`, SSH.
- **integration** (~3 min): child CLI and/or **local** `addprocs`. Not
  real SSH / rsync.
- **e2e** (~15–25 min): real SSH + rsync, two Linux workers; every PR
  (Compose). Not local-only CLI wiring.
- **e2e weekly** (10–50 min): same `e2e.jl` from Linux, macOS Intel, or
  WSL2 (not a PR check; required after a `cut` merge before register).
  Not macOS workers.
- **doctests** (~5 s): `src/` docstring examples (Documenter, Julia 1.12).
  Not workers / SSH.

## Registry tree

[PkgEval](https://github.com/JuliaCI/PkgEval.jl) (via
[Nanosoldier](https://github.com/JuliaCI/Nanosoldier.jl)) and `Pkg.add` use
a Registry tarball, not this checkout. This package:
<https://juliaci.github.io/NanosoldierReports/pkgeval_badges/D/DistSSHKit.html>
Latest ecosystem report:
<https://juliaci.github.io/NanosoldierReports/pkgeval_badges/report.html>
Reproduce that tree: copy without kit `.git` / `Manifest.toml`, `Pkg.add`
from a **bare** `file://` git (so the installed package dir has no `.git` —
DistSSHKit talks to git for jobs, not for its own install), `chmod a-w` on
`pkgdir`, then `Pkg.test`. Do this after changing the gates above, and
before a General cut. CI: `Pkg.test - registry tree` on heavy PRs,
**main**, and **cut** (slot tip, no `ssh`; not a required check).

Copy without `Manifest.toml` (and without `.git`). On Linux, `mktemp -d` is
enough. On macOS, put the copy under `$HOME` if you will bind-mount it into
Docker Desktop (`$TMPDIR` / `/tmp` mount empty).

```bash
WORKDIR=$(mktemp -d "$HOME/dsk.XXXXXX")
rsync -a \
  --exclude .git \
  --exclude Manifest.toml \
  --exclude docs/Manifest.toml \
  --exclude docs/build \
  --exclude test/artifacts \
  ./ "$WORKDIR/"
```

This machine (min / max / `+nightly`). Distro `ssh` / `git` stay on `PATH`.
On Linux this is enough for the tree; it does not reproduce a missing
`ssh`. Do not `git init` inside the copy (that would put `.git` on the kit
tree). Use a bare repo, then `Pkg.add(; url=)`.

```bash
BARE=$(mktemp -d "$HOME/dsk.git.XXXXXX")
git init --bare -q "$BARE"
git --git-dir="$BARE" --work-tree="$WORKDIR" add -A
git --git-dir="$BARE" --work-tree="$WORKDIR" \
  -c user.email=ci@distsshkit -c user.name=ci commit -q -m tree
```

```bash
julia -e '
  using Pkg
  Pkg.activate(temp=true)
  Pkg.add(; url=ARGS[1])
  using DistSSHKit
  run(Cmd(["chmod", "-R", "a-w", pkgdir(DistSSHKit)]))
  Pkg.test("DistSSHKit")
' "file://$BARE"
```

Linux without `ssh`: same [juliaup](https://github.com/JuliaLang/juliaup)
Ubuntu container from macOS or from Linux
([Docker Hub `julia`](https://hub.docker.com/_/julia) has no `nightly`
tag). `--no-install-recommends` keeps `openssh-client` out.

```bash
docker run --rm \
  -v "$WORKDIR:/pkg:ro" \
  ubuntu:24.04 \
  bash -lc "
    apt-get update -qq &&
    apt-get install -y -qq --no-install-recommends \
      curl ca-certificates git &&
    curl -fsSL https://install.julialang.org |
      sh -s -- --yes --default-channel nightly &&
    export PATH=\"\$HOME/.juliaup/bin:\$PATH\" &&
    cp -a /pkg /tmp/dsk &&
    git init --bare -q /tmp/dsk.git &&
    git --git-dir=/tmp/dsk.git --work-tree=/tmp/dsk add -A &&
    git --git-dir=/tmp/dsk.git --work-tree=/tmp/dsk \
      -c user.email=ci@distsshkit -c user.name=ci \
      commit -q -m tree &&
    julia +nightly -e '
      using Pkg
      Pkg.activate(temp=true)
      Pkg.add(; url=\"file:///tmp/dsk.git\")
      using DistSSHKit
      run(Cmd([\"chmod\", \"-R\", \"a-w\", pkgdir(DistSSHKit)]))
      Pkg.test(\"DistSSHKit\")
    '
  "
```

## SSH E2E

Two Linux workers. `DISTSSHKIT_SSH_E2E=1`. Controller OS matrix:
[`testenv/docker-ssh/README.md`](../testenv/docker-ssh/README.md). Apple
silicon without Compose:
[apple-container-ssh README](../testenv/apple-container-ssh/README.md)
(`./scripts/up.sh --e2e`).

Open logs with [`test/artifacts/README.md`](artifacts/README.md):

```bash
open "$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt"
```

Coverage uploads on **main push** (`Pkg.test` max) and **E2E weekly** /
**`cut` PR** E2E (`DISTSSHKIT_CODE_COVERAGE=1` on `up.sh --e2e`). Ordinary
PR E2E has no coverage. Local:

```bash
DISTSSHKIT_CODE_COVERAGE=1 \
  testenv/docker-ssh/scripts/up.sh --e2e
```

### Setup (rsync tree)

- Julia resolve: controller and remotes share major.minor
- `run_on_host`: `--version` exit 0; `-e exit(3)` is `.exitcode == 3`
  (no throw)
- `--delete`: remote `Project.toml` is gone
- `--rsync`: remote `Project.toml` exists
- `--instantiate` / `--check`: job deps; Julia version (no
  `--ignore-julia-version`)
- `--runtest`: job `Pkg.test` pass; a planted failure is non-zero
- `--rsync` nonempty: refused
- `~/…` remote path: delete → rsync → instantiate → drive still run

### Drive / go / size

`square_file` writes the CSV in `main()` on the **controller**. Workers
only return numbers. Collect tests use files workers write.

- `size`: both hosts, `GB`, `Total:`
- `square_echo`: remote compute; stdout has `param^2:`
- `square_file`: local CSV exists; absent on the remote
- `worker_*.txt`: on the worker; `run_on_host` read;
  `--collect-missing` restores; skip keeps junk;
  `--collect-overwrite` replaces; `kit.result` `hosts` names both
  remotes
- `kit.progress`: `kit_progress_latest` last event is `done` after demo
  drive / go
- worker `error(...)`: non-zero
- mixed `parent:1` + two remotes: smoke `nw=3`
- in-process `drive!` twice (reentrant): each call `nw=2`; no worker
  leak (#144)
- detached drive SIGKILL: wait until heartbeat monitors start, then
  remote `--worker` gone (#148)
- `go pi_echo`: π on both hosts
- `go --rsync` empty dedicated root: no prior `--instantiate`; π on
  both; remote `Project.toml` appears
- `go pi_file`: slot `pi_results.txt` after go collect;
  `DISTSSHKIT_JOB_ID` set so remote `-L` mark is collected
- `go --output-dir`: `pi_results.txt` under the given batch root
- API: `setup!` / `go!(output_dir=)` / `pipeline!(collect=true)` on
  worker files

### Git (separate remote root)

- `--clone` / `--instantiate` / `--check`: remote hash matches
- `--require-git` after a local bump: fails
- `--sync` then `--require-git`: pass
- `--pull` after controller `git push`: `e2e_sync_marker.txt` on the
  workers matches

Child-1 can SSH to child-2 (compose DNS).

Not this file: macOS workers, dead hosts, fake `ssh`/`rsync`, local
`with_kit` recipes (`test/integration/demos/`).

## Fakes vs real SSH

- **setup:** core work is `ssh` / `rsync`. `Pkg.test()` uses fixtures
  `DISTSSHKIT_TEST_SSH` / `_RSYNC`. Bytes on a real remote: e2e.
- **drive / go:** core work is `Distributed` workers. `Pkg.test()` uses
  real **local** `addprocs` (no SSH fake). Bytes on a real remote: e2e.
- **drive collect:** core work is `ssh` / `rsync` of result trees.
  `Pkg.test()` uses the same fakes, **control flow only** (fake rsync
  does not copy). Bytes on a real remote: e2e.
- **size:** plan math (+ optional RSS). `Pkg.test()` is unit + local
  probe in `integration/size/`. Bytes on a real remote: e2e if needed.

Do not fake Julia SSH worker launch. Local workers stand in for drive/go;
they cannot stand in for setup. `_run_kit_setup` / `_run_kit_go` use an
ephemeral project unless `project_root` is set (E2E uses
`test/artifacts/ssh-e2e/`).

## Host tokens vs SSH names

Tests follow the same two surfaces as the kit. No extra test harness:

- go / drive / size CLI and `KitSession(workers=…)` use placement tokens
  (`parent:2`, `child:host-a:4`)
- setup, collect-only HOST, fake SSH trees, `session.hosts`, and
  `HostRunResult.host` use the SSH name (`host-a`)
- `_sample_hosts_file` is tokens; `_sample_setup_hosts_file` is bare
  names

Do not search-replace a host name into a token (that produced
`child:child:…` and collect dirs named `child:host1`).

## Writing tests

1. Add under `unit/` (src mirror) or `integration/<area>/`.
2. Top-level `include` in `runtests.jl` (JETLS follows that). Do not
   register `e2e.jl` there (`Pkg.test` must not SSH). `e2e.jl` is its own
   JETLS entry in `.github/jetls-check.sh`.
3. Subprocess helpers in `support/`; one-off scripts in `fixtures/`.
4. Short Oracle / non-guarantee comment at the top of the file.
5. Pin verbosity with `with_kit_verbosity` if you assert kit detail
   lines. `Pkg.test` defaults to `:progress`. `kit_confirm` and consent
   warnings must show in `:quiet`, `:progress`, and `:verbose`.

Helpers (via `support.jl`): `_child_julia_env`, `_run_kit_drive` /
`_run_kit_setup` / `_run_kit_go` / `_run_kit_size`, `_mktemp_host` /
`_with_tempdir` / `_stage_with_kit_demos!`, `_with_ssh_e2e_suite`,
`_capture_stdio` / `with_kit_verbosity`.

- `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL` (default `1` in test children):
  skip remote / `setup --cleanup` `pkill`; each child `rmprocs`es its own
  local workers
- `DISTSSHKIT_SSH_E2E` (unset): `1` runs `test/e2e.jl` (needs docker-ssh
  workers)
- `DISTSSHKIT_CODE_COVERAGE` (unset): `1` with `up.sh --e2e` →
  `--code-coverage=user`

CLI also honors `DISTSSHKIT_QUIET`, `DISTSSHKIT_PROGRESS`,
`DISTSSHKIT_VERBOSE`, `DISTSSHKIT_YES`, `DISTSSHKIT_HOSTS`,
`DISTSSHKIT_HOSTS_FILE` (`src/DistSSHKit/argv/session.jl`).

## Aqua

CI and [`.github/aqua-check.sh`](../.github/aqua-check.sh) `Pkg.add("Aqua")`
with no version pin. `Pkg` is a module dep (`using Pkg` in
`src/DistSSHKit.jl`) so Aqua `stale_deps` can run.
