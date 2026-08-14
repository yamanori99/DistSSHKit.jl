# Contributing

How to work on this repository. Users: [Documenter](https://yamanori99.github.io/DistSSHKit.jl/stable/) (`docs/`) and [README.md](README.md). Dev docs: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/).

## Requirements

- macOS / Linux / WSL2 Ubuntu (not native Windows; the kit shells out to `ssh` / `rsync` / POSIX tools)
- Julia **1.10+** for the library and `Pkg.test()`; **1.12+** for `julia -m DistSSHKit` and docs (`~1.13.0-0` when available). Prefer [juliaup](https://github.com/JuliaLang/juliaup); details in [Requirements](https://yamanori99.github.io/DistSSHKit.jl/dev/requirements/).
- SSH work: Git, OpenSSH, rsync. Match **major.minor** with remotes (CI E2E workers are 1.12). Daily / Run workflow: `E2E daily` (`macos-15-intel` / WSL2 → `ubuntu-24.04`)

## Setup

```bash
git clone https://github.com/yamanori99/DistSSHKit.jl.git
cd DistSSHKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Edit the kit from another app:

```bash
julia --project=/path/to/MyProject.jl -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHKit.jl")'
```

On 1.12+, `julia --project=. -m DistSSHKit …` works the same as after `Pkg.add`. On 1.10–1.11 use `go!` / `drive!` or [`main`](https://yamanori99.github.io/DistSSHKit.jl/stable/api/).

## Test

Required before sharing or tagging (run on 1.10+, and 1.12 / `~1.13.0-0` when you can):

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Smoke (1.12+; same as [`demos/README.md`](demos/README.md)):

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
```

SSH / sync / worker changes: [`testenv/docker-ssh/scripts/up.sh --e2e`](testenv/docker-ssh/README.md) (macOS controllers included). Optional Mac-only workers (not CI): [`testenv/apple-container-ssh`](testenv/apple-container-ssh).

CI (fast on every PR, slow OS on a timer):

- **PR / `main`:** `Test / Pkg.test - Julia * - ubuntu-latest`, `Lint / JETLS - Julia * - ubuntu-latest`, `Docs / Documenter - Julia 1.12 - ubuntu-latest`, `Scan / Gitleaks`. Root-markdown-only PRs keep those check names but skip the suite. `E2E / ubuntu-latest → ubuntu-24.04` always appears; the suite runs when `src/`, `test/`, `demos/`, `testenv/`, `Project.toml`, or the E2E workflow change.
- **Daily 04:00 JST / Run workflow `E2E daily`:** `ubuntu-latest (image)`, `macos-15-intel → ubuntu-24.04`, `windows-latest (WSL2) → ubuntu-24.04`.
- **Assets path:** `Assets / bake SVG`.

Optional: [`.github/jetls-check.sh`](.github/jetls-check.sh) ([JETLS](https://github.com/aviatesk/JETLS.jl); same files as CI, fails on hint+). CI uses `aviatesk/JETLS.jl/.github/actions/check@release` on Julia 1.12 and 1.13. Docs (`julia --project=docs -e 'using Pkg; Pkg.instantiate()'` then `julia --project=docs --color=yes docs/make.jl`), logo bake (`julia docs/src/assets/bake.jl`, plus `--png` / `--gif`), [gitleaks](https://github.com/gitleaks/gitleaks) (`gitleaks detect --source .`).

Language Server `IncorrectCallArgs` is not CI (JETLS is). Do not add `.vscode/settings.json` to silence it.

## Workflow

- Branch from `main` (`feature/…`, `fix/…`, `docs/…`, `chore/…`). Open a PR; `main` is squash-merge only. Keep each PR one reviewable change — split unless `main` would be broken in between. Large plans: Discussion / Enhancement Issue first, then small PRs.
- Breaking (CLI names, module name, driver `init_output_dir!` / `main`, …): bump `x` in `0.x.y`. Patch `y` only otherwise. Tags (`vX.Y.Z`) are a maintainer decision after merge. TagBot.yml waits for a General-registry release.
- `setup --clone` / `--rsync` refuse a non-empty destination; redeploy with `setup --delete`. Prefer first deploy `--rsync`; git updates `--sync` / `--pull`. Do not weaken that refusal without tests.

## Errors: diagnose then explain

Tip-bearing failures (CLI vs bang API often need different next commands):

1. **Diagnose** — facts only (`kind`, paths, …). No finished English prose.
2. **Explain** — format for `surface=:cli` or `:api` (command wording only).

Helpers: `src/DistSSHKit/explain.jl`. Surface lives on `KitCliSession` / `hint_surface(session)` (`:cli` from CLI, `:api` from `KitSession`). Domain tips stay next to the domain (`demos.jl` for demo-install). Parse-only `ArgumentError`s may stay plain strings. Do not grow an issue/remedy type hierarchy until several domains share a shape.

## Issues and Discussions

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. Form area picks are triage text — add `area:*` when useful. `breaking` is a PR label, not an Issue type. Usage questions are not Issues.

**Discussions**: Q&A, Ideas (promote to an Enhancement Issue when tracking), General, Show and tell, Polls, Announcements. Confirmed bugs are not Discussions. Security: [SECURITY.md](SECURITY.md).

## PR labels

Path labels come from generated `.github/labeler.yml`:

```bash
./.github/gen-labeler.sh          # rewrite
./.github/gen-labeler.sh --check  # CI drift
```

`src/cli/<area>/` → `area:<area>`; `explain` / `demos` are also path-auto. No catch-all `area:kit`. New CLI area: regenerate, commit, create the GitHub label if needed.

Every PR needs **one** type label. CI infers from the branch prefix: `feat/`/`feature/` → `enhancement`; `fix/`/`bug/`/`hotfix/` → `bug`; `breaking/`/`break/` → `breaking`; `chore/`/`docs/`/`ci/`/`build/`/`test/`/`refactor/` and anything else → `chore`. Override with `gh pr edit N --add-label …`. Unknown prefixes do not fail the check.

`breaking` may combine with `bug` / `enhancement` / `chore`. It flags a version cut (`0.x.y` bump `x`, or major after `1.0`); the `Project.toml` bump is a separate decision.

Dependabot is exempt from the type-label check (`dependencies` only; path labels like `ci` still apply). Do not add type labels there.

## Language and AI

`.jl` sources (comments, docstrings, errors): English. User-facing docs: update `docs/src/*.md` and [README.md](README.md) when install or Docs links change. Generative AI is allowed; understand and verify what you submit. Keep docs plain; avoid hype.
