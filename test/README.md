# Tests

How the DistSSHKit test suite is organized. For the full maintainer checklist, see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the kit checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Tests run sequentially (`Test.@testset` nesting). `Pkg.test()` activates `test/Project.toml` (fixtures, path dependency on `..`). Aqua is a separate CI job.

## Layout

```text
test/
  runtests.jl          # Pkg.test() entry (unit + integration)
  e2e.jl               # real OpenSSH; not Pkg.test()
  support.jl           # includes support/*.jl
  support/             # shared helpers (subprocess, drive, staging, …)
  unit/                # in-process; no child julia, no addprocs
  integration/         # child julia and/or local addprocs
  fixtures/            # small driver scripts copied into temp host projects
  Project.toml         # test environment
```

`unit/` mirrors `src/`:

```text
unit/
  DistSSHKit/          # ↔ src/DistSSHKit/ (module API + setup cores + argv parsers)
    argv/              # ↔ DistSSHKit/argv/
    setup/             # ↔ DistSSHKit/setup/
  cli/                 # ↔ src/cli/ (CLI entry wiring, using_guard)
    drive/, go/, setup/, size/   # argv / help tests call DistSSHKit.parse_*
```

`integration/` is grouped by CLI/area name (`drive/`, `demos/`, `setup/`, `go/`, `size/`).

Real OpenSSH E2E is `test/e2e.jl` (not part of `Pkg.test()`).
How to run: [`testenv/docker-ssh/README.md`](../testenv/docker-ssh/README.md).

## Layers

Green on one layer does not imply the others. `Pkg.test()` does not run `test/e2e.jl`.

| Layer | Guarantees | Does not guarantee | Typical runtime |
| --- | --- | --- | --- |
| **JETLS** (independent) | types / hints on entry files | runtime behavior | — |
| **Aqua** (independent; latest registry Aqua) | ambiguities, exports, compat, project consistency | CLI / workers | ~5 s |
| **unit** | in-process facts (parse, paths, fake setup ops, missing-script throws) | child julia, `addprocs`, SSH | ~30 s |
| **integration** | child `julia` CLI and/or **local** `addprocs` (`-m` on 1.12+; `main` on 1.10–1.11) | real SSH / rsync | ~2 min |
| **e2e** (`test/e2e.jl`; `E2E / ubuntu-latest → ubuntu-24.04`) | real SSH + rsync against Docker workers (`DISTSSHKIT_SSH_E2E=1`). CI: every PR | local-only CLI wiring | ~10–20 min |
| **e2e Linux daily** (`E2E daily / ubuntu-latest → ubuntu-24.04`) | Same suite on the daily timer (not a PR check). Pulls the worker image | — | ~10–20 min |
| **e2e macOS** (`E2E daily / macos-15-intel → ubuntu-24.04`) | Same suite from **macOS Intel** + Colima. Daily 04:00 JST or Run workflow `E2E daily` | — | ~25–50 min |
| **e2e WSL** (`E2E daily / windows-latest (WSL2) → ubuntu-24.04`) | Same suite from WSL2. Daily / Run workflow. Not native Windows | — | ~20–45 min |
| **doctests** (`Docs / Documenter - Julia 1.12 - ubuntu-latest`) | docstring examples in `src/` | worker / SSH | ~5 s |

Most of the wall time in `Pkg.test()` is integration (child Julia + local workers).
Remote SSH on PRs and main is **E2E / ubuntu-latest → ubuntu-24.04**. Daily / Run workflow `E2E daily`: **ubuntu-latest**, **macos-15-intel**, and **WSL2** against `ubuntu-24.04` workers. Doctests run in **Docs / Documenter - Julia 1.12 - ubuntu-latest**, not `Pkg.test()`. **Test / Pkg.test - Julia 1.10 - ubuntu-latest** / **1.11** uses `DistSSHKit.main` for CLI children (`-m` is 1.12+).

## Why only `setup` uses SSH/rsync fakes

Commands differ in what their core work is:

| Command | Core work | How `Pkg.test()` covers it | Real remote |
| --- | --- | --- | --- |
| **setup** | Shells out to `ssh` / `rsync` | Fake doubles (`DISTSSHKIT_TEST_SSH`, `DISTSSHKIT_TEST_RSYNC` in `test/fixtures/`) | ssh-e2e |
| **drive** / **go** | Julia `Distributed` workers | Real **local** `addprocs` (no SSH fake) | ssh-e2e |
| **size** | Plan math (+ optional remote RSS via `addprocs`) | Pure unit for planning; local probe worker in `integration/size/measure.jl` | ssh-e2e if needed |

Local workers are a cheap real substitute for drive/go (same Julia worker path, no Docker).
They cannot substitute for setup: copying/deleting a remote tree needs `ssh`/`rsync`, so unit tests swap those binaries for fakes. Do not add the same style of fake for drive/go/size; faking Julia SSH worker launch would be a different, heavier double, and local + ssh-e2e already split that coverage.

Setup/go CLI subprocess helpers (`_run_kit_setup` / `_run_kit_go`) use an
ephemeral project when `project_root` is omitted, so those runs do not leave
`.distsshkit/` logs in the kit checkout. SSH E2E keeps durable runs under
`test/artifacts/ssh-e2e/` (gitignored).

## Support helpers

Loaded via `support.jl`:

- `_child_julia_env` — child-process `ENV` (drops `JULIA_LOAD_PATH` and in-process CLI-done flags, sets `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1`)
- `_run_kit_drive` / `_run_host_drive` / `_run_kit_setup` / `_run_kit_go` / `_run_kit_size` — CLI subprocesses
- `_mktemp_host`, `_with_tempdir`, `_stage_with_kit_demos!` — isolated temp host projects with bundled `with_kit` demos
- `_with_ssh_e2e_suite`, `_stage_ssh_e2e_remote_host!` — SSH E2E suite + scratch projects

## Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL` | `1` in test children (automatic) | Skip broad `pkill` in drive; each subprocess cleans up its own workers via `rmprocs` |
| `DISTSSHKIT_SSH_E2E` | unset | Set to `1` to run `test/e2e.jl` (requires `testenv/docker-ssh` workers) |

SSH E2E keeps one suite dir under `test/artifacts/ssh-e2e/`. Open
`SUMMARY.txt` only (see [`test/artifacts/README.md`](artifacts/README.md)).

```bash
open "$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt"
rm -rf test/artifacts/ssh-e2e
```

Kit CLI flags (drive / go / setup / size) also honor `DISTSSHKIT_QUIET`, `DISTSSHKIT_PROGRESS`, `DISTSSHKIT_VERBOSE`, `DISTSSHKIT_YES`, `DISTSSHKIT_HOSTS`, and `DISTSSHKIT_HOSTS_FILE`; see `src/DistSSHKit/argv/session.jl`.

## Adding tests

1. Add a file under `unit/` (src mirror) or `integration/<area>/` (failure mode).
2. Add a top-level `include` in `runtests.jl` (JETLS follows that; do not wrap it in a function). Do not register `test/e2e.jl` there.
3. Reuse `support/` helpers for subprocess work; put one-off scripts in `fixtures/`.
4. Put a short Oracle / non-guarantee comment at the top of the file.

## Aqua note

Aqua is not in `Pkg.test()`. CI (and [`.github/aqua-check.sh`](../.github/aqua-check.sh)) develops the kit in a temp env and `Pkg.add("Aqua")` with no version pin. `Pkg` is a module dependency (`using Pkg` in `src/DistSSHKit.jl`) so Aqua's `stale_deps` can run.
