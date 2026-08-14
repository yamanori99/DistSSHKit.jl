# Tests

How the DistSSHKit test suite is organized. For the full maintainer checklist, see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the kit checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Tests run sequentially (`Test.@testset` nesting). `Pkg.test()` activates `test/Project.toml` (Aqua, fixtures, path dependency on `..`).

## Layout

```text
test/
  runtests.jl          # entry point
  aqua.jl              # Aqua.jl QA
  support.jl           # includes support/*.jl
  support/             # shared helpers (subprocess, drive, staging, …)
  unit/                # fast, in-process tests
  integration/         # subprocess / drive smoke tests (slow)
  fixtures/            # small driver scripts copied into temp host projects
  Project.toml         # test environment
```

`unit/` mirrors `src/`:

```text
unit/
  DistSSHKit/          # ↔ src/DistSSHKit/ (module API + setup cores + argv parsers)
    cli/               # ↔ DistSSHKit/cli/
    setup/             # ↔ DistSSHKit/setup/
  cli/                 # ↔ src/cli/ (CLI entry wiring: using_guard, setup exit)
    drive/, go/, setup/, size/   # argv / help tests call DistSSHKit.parse_*
```

`integration/` groups drive smokes and demo recipe runs.

Real OpenSSH E2E lives under `integration/ssh/` (not part of `Pkg.test()`).
How to run: [`testenv/docker-ssh/README.md`](../testenv/docker-ssh/README.md).

## Layers

| Layer | What it checks | Typical runtime |
| --- | --- | --- |
| **Aqua** (`aqua.jl`) | ambiguities, exports, compat, project consistency | ~5 s |
| **unit** | parsing, display, module helpers, CLI arg tables | ~5 s |
| **integration** | kit CLI `drive` / `go` in child processes (`-m` on 1.12+; `main` on 1.10–1.11) | ~2 min |
| **ssh-e2e** (`E2E / Linux → Linux`) | Real SSH + rsync against Docker workers (`DISTSSHKIT_SSH_E2E=1`). CI: every PR | ~10–20 min |
| **ssh-e2e macOS** (`E2E / macOS → Linux`) | Same suite from **macOS Intel** + Colima. Daily 04:00 JST or Run workflow. Pulls the worker image the Linux job pushed | ~25–50 min |
| **ssh-e2e WSL** (`E2E / WSL2 → Linux`) | Same suite from **WSL2 Ubuntu**. Daily / dispatch. Not native Windows | ~20–45 min |
| **doctests** (`Docs / Documenter - Julia 1.12`) | docstring examples in `src/` (`Documentation.yml`) | ~5 s |

Most of the wall time in `Pkg.test()` is integration (child Julia + local workers).
Remote SSH on PRs and main is **E2E / Linux → Linux**. Daily / dispatch: **E2E / macOS → Linux** and **E2E / WSL2 → Linux**. Doctests run in **Docs / Documenter - Julia 1.12**, not `Pkg.test()`. **Test / Pkg.test - Julia 1.10** / **1.11** uses `DistSSHKit.main` for CLI children (`-m` is 1.12+).

## Why only `setup` uses SSH/rsync fakes

Commands differ in what their core work is:

| Command | Core work | How `Pkg.test()` covers it | Real remote |
| --- | --- | --- | --- |
| **setup** | Shells out to `ssh` / `rsync` | Fake doubles (`DISTSSHKIT_TEST_SSH`, `DISTSSHKIT_TEST_RSYNC` in `test/fixtures/`) | ssh-e2e |
| **drive** / **go** | Julia `Distributed` workers | Real **local** `addprocs` (no SSH fake) | ssh-e2e |
| **size** | Plan math (+ optional remote RSS via `addprocs`) | Pure unit for planning; no SSH fake | ssh-e2e if needed |

Local workers are a cheap real substitute for drive/go (same Julia worker path, no Docker).
They cannot substitute for setup: copying/deleting a remote tree needs `ssh`/`rsync`, so unit tests swap those binaries for fakes. Do not add the same style of fake for drive/go/size; faking Julia SSH worker launch would be a different, heavier double, and local + ssh-e2e already split that coverage.

Setup/go CLI subprocess helpers (`_run_kit_setup` / `_run_kit_go`) use an
ephemeral project when `project_root` is omitted, so unit runs do not leave
`.distsshkit/` logs in the kit checkout. SSH E2E keeps durable runs under
`test/artifacts/ssh-e2e/` (gitignored).

## Support helpers

Loaded via `support.jl`:

- `_child_julia_env` — child-process `ENV` (drops `JULIA_LOAD_PATH`, sets `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1`)
- `_run_kit_drive` / `_run_host_drive` / `_run_kit_setup` / `_run_kit_go` / `_run_kit_size` — CLI subprocesses
- `_mktemp_host`, `_with_tempdir`, `_stage_with_kit_demos!` — isolated temp host projects with bundled `with_kit` demos
- `_with_ssh_e2e_suite`, `_stage_ssh_e2e_remote_host!` — SSH E2E suite + scratch projects
- `_run_test_files!` — sequential test-file includes

## Environment variables

| Variable | Default | Effect |
| --- | --- | --- |
| `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL` | `1` in test children (automatic) | Skip broad `pkill` in drive; each subprocess cleans up its own workers via `rmprocs` |
| `DISTSSHKIT_SSH_E2E` | unset | Set to `1` to run `test/integration/ssh/run.jl` (requires `testenv/docker-ssh` workers) |

SSH E2E keeps one suite dir under `test/artifacts/ssh-e2e/`. Open
`SUMMARY.txt` only (see [`test/artifacts/README.md`](artifacts/README.md)).

```bash
open "$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt"
rm -rf test/artifacts/ssh-e2e
```

Kit CLI flags (drive / go / setup / size) also honor `DISTSSHKIT_QUIET`, `DISTSSHKIT_PROGRESS`, `DISTSSHKIT_VERBOSE`, `DISTSSHKIT_YES`, `DISTSSHKIT_HOSTS`, and `DISTSSHKIT_HOSTS_FILE`; see `src/DistSSHKit/cli/session.jl`.

## Adding tests

1. Add a file under `unit/` or `integration/` (follow the existing directory naming).
2. Register its path in `_unit_test_files()` or `_integration_test_files()` in `runtests.jl`.
3. Reuse `support/` helpers for subprocess work; put one-off scripts in `fixtures/`.

## Aqua note

`runtests.jl` and `aqua.jl` both `using DistSSHKit` as the package (root project or `test/Project.toml` `[sources]`). `Pkg` is a module dependency (`using Pkg` in `src/DistSSHKit.jl`) so Aqua's `stale_deps` can run.
