# Contributing

How to work on this repository. Users: [Documenter](https://yamanori99.github.io/DistSSHKit.jl/stable/) (`docs/`), [README.md](README.md), and [NEWS.md](NEWS.md). Dev docs: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/).

## Requirements

- macOS / Linux / WSL2 Ubuntu (not native Windows; the kit shells out to `ssh` / `rsync` / POSIX tools)
- Julia **1.10+** for the library and `Pkg.test()`; **1.12+** for `julia -m DistSSHKit` and docs (`~1.13.0-0` when available). Prefer [juliaup](https://github.com/JuliaLang/juliaup); details in [Requirements](https://yamanori99.github.io/DistSSHKit.jl/dev/requirements/).
- SSH work: Git, OpenSSH, rsync. Match **major.minor** with remotes (CI E2E workers are 1.12). Daily / Run workflow: `E2E daily` (`ubuntu-latest` / `macos-15-intel` / WSL2 → `ubuntu-24.04`)

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

SSH / sync / worker changes: [`testenv/docker-ssh/scripts/up.sh --e2e`](testenv/docker-ssh/README.md) (macOS controllers included). `Pkg.test()` Green does not cover real SSH; that suite is `test/e2e.jl` (independent gate). To skip building the worker image: `DISTSSHKIT_WORKER_IMAGE=ghcr.io/yamanori99/distsshkit-linux-ssh-worker:latest`. Optional Mac-only workers (not CI): [`testenv/apple-container-ssh`](testenv/apple-container-ssh).

CI (fast on every PR, slow OS on a timer):

- **PR / `main`:** `Test / Pkg.test - Julia * - ubuntu-latest`, `Lint / JETLS - Julia * - ubuntu-latest`, `Aqua / Aqua - Julia * - ubuntu-latest`, `Docs / Documenter - Julia 1.12 - ubuntu-latest`, `Scan / Gitleaks`. PRs that only touch `README.md`, `CONTRIBUTING.md`, `NEWS.md`, `SECURITY.md`, `LICENSE`, `.gitignore`, or `.github/pull_request_template.md` skip Pkg.test / JETLS / Aqua / Documenter (Skipped, not a green pass; required checks still succeed). A new root markdown file is heavy until it is added to [`.github/actions/ci-heavy/action.yml`](.github/actions/ci-heavy/action.yml). `docs/src` still runs Documenter (and Pkg.test / JETLS / Aqua). `E2E / ubuntu-latest → ubuntu-24.04` is skipped unless `src/`, `test/`, `demos/`, `testenv/`, `Project.toml`, or the E2E workflow change.
- **Daily 04:00 JST / Run workflow `E2E daily`:** `ubuntu-latest (image)`, `ubuntu-latest → ubuntu-24.04`, `macos-15-intel → ubuntu-24.04`, `windows-latest (WSL2) → ubuntu-24.04`. Not a PR check (PR Linux E2E stays on `E2E`). A failed run opens (or comments on) an Issue titled `E2E daily failed` (`ci`); a later green run closes it. README badge tracks `main`.
- **Assets path:** `Assets / bake SVG`.

Optional: [`.github/jetls-check.sh`](.github/jetls-check.sh) ([JETLS](https://github.com/aviatesk/JETLS.jl); same files as CI, fails on hint+). CI uses `aviatesk/JETLS.jl/.github/actions/check@release` on Julia 1.12 and 1.13 — that tag moves, so after a JETLS CLI/action bump re-read [`cli-check`](https://aviatesk.github.io/JETLS.jl/dev/cli-check/) and confirm `--exit-severity=hint` still fails on hint+ and that hints still print (`--show-severity` defaults to `hint` today; the script does not pin it). Aqua is not in `Pkg.test()`; CI and [`.github/aqua-check.sh`](.github/aqua-check.sh) `Pkg.add("Aqua")` in a temp env (latest registry, no compat pin). Docs (`julia --project=docs -e 'using Pkg; Pkg.instantiate()'` then `julia --project=docs --color=yes docs/make.jl`), logo bake (`julia docs/src/assets/bake.jl`, plus `--png` / `--gif`), [gitleaks](https://github.com/gitleaks/gitleaks) (`gitleaks detect --source .`).

Language Server `IncorrectCallArgs` is not CI (JETLS is). `.vscode/settings.json` is gitignored; do not commit it to silence the LS.

Optional: [Fatou](https://fatou.dev) (formatter / lint / LSP locally; no Julia runtime). Not CI — JETLS stays the gate. Style and parser are still moving; after a Fatou bump, check it did not rewrite files you did not mean to touch. Do not add `fatou.toml` or Fatou to `.vscode/extensions.json`.

## Workflow

- Branch from `main` (`feature/…`, `fix/…`, `docs/…`, `chore/…`). Open a PR; `main` is squash-merge only. Keep each PR one reviewable change — split unless `main` would be broken in between. Large plans: Discussion / Enhancement Issue first, then small PRs. Merged head branches are deleted automatically (repo Settings).
- Breaking (CLI names, module name, driver `init_output_dir!` / `main`, …): `breaking` on the PR. Bump `x` in `0.x.y` when you cut that line; patch `y` otherwise. `cut` is any `version` raise. Tags (`vX.Y.Z`) after a registry release are normally cut by TagBot ([`.github/workflows/TagBot.yml`](.github/workflows/TagBot.yml)). Repo Settings → Actions → Workflow permissions must be **Read and write** (`GITHUB_TOKEN`). Maintainers may still `git tag -a` when needed. Date the matching [NEWS.md](NEWS.md) section `YYYY-MM-DD` UTC on the tag day. On `@JuliaRegistrator register`, paste that section under `Release notes:` so the GitHub Release matches (TagBot's PR list is the default if you skip this).
- `setup --clone` / `--rsync` refuse a non-empty destination; redeploy with `setup --delete`. Prefer first deploy `--rsync`; git updates `--sync` / `--pull`. Do not weaken that refusal without tests.

## Errors: diagnose then explain

Tip-bearing failures (CLI vs bang API often need different next commands):

1. **Diagnose** — facts only (`kind`, paths, …). No finished English prose.
2. **Explain** — format for `surface=:cli` or `:api` (command wording only).

Helpers: `src/DistSSHKit/explain.jl`. Surface lives on `KitCliSession` / `hint_surface(session)` (`:cli` from CLI, `:api` from `KitSession`). Domain tips stay next to the domain (`demos.jl` for demo-install). Parse-only `ArgumentError`s may stay plain strings. Do not grow an issue/remedy type hierarchy until several domains share a shape.

## Issues and Discussions

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. Form area picks are triage text — add `area:*` when useful. `breaking` and `cut` are PR labels, not Issue types. Usage questions are not Issues.

**Discussions**: Q&A, Ideas (promote to an Enhancement Issue when tracking), General, Show and tell, Polls, Announcements. Confirmed bugs are not Discussions. Registry cuts do not need an Announcements post; the GitHub Release is enough. Direction: [Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26). Security: [SECURITY.md](SECURITY.md).

## PR labels

Path labels come from generated `.github/labeler.yml`:

```bash
./.github/gen-labeler.sh          # rewrite
./.github/gen-labeler.sh --check  # CI drift
```

`src/cli/<area>/` → `area:<area>`; `explain` / `demos` are also path-auto. No catch-all `area:kit`. New CLI area: regenerate, commit, create the GitHub label if needed.

Every PR needs **one** type label. CI infers, in order: a unique `bug` / `enhancement` / `chore` on a closing issue (`Fixes #N`); else the branch prefix (`feat/`/`feature/` → `enhancement`; `fix/`/`bug/`/`hotfix/` → `bug`; `breaking/`/`break/` → `breaking`; `chore/`/`docs/`/`ci/`/`build/`/`test/`/`refactor/` and anything else → `chore`). `fix/` plus `Fixes` an enhancement issue gets `enhancement`. Override with `gh pr edit N --add-label …`. Unknown prefixes do not fail the check.

`breaking` may combine with `bug` / `enhancement` / `chore`. It means the PR's **behavior** is incompatible (CLI names, dropped API, …). `cut` means `Project.toml` `version` went up (`0.2.1` → `0.2.2` or `0.3.0`). They are independent: a breaking change can land without bumping; a cut PR can bump only. CI adds `cut` when that version string increases (not an unrelated `Project.toml` edit). After merge, a human `@JuliaRegistrator register`s; TagBot tags once General has the release.

Dependabot is exempt from the type-label check (`dependencies` only; path labels like `ci` still apply). Do not add type labels there.

## Language and AI

`.jl` sources (comments, docstrings, errors): English. User-facing docs: update `docs/src/*.md` and [README.md](README.md) when install or Docs links change; user-visible behavior in [NEWS.md](NEWS.md) (date the section when tagged). Generative AI is allowed; understand and verify what you submit. Keep docs plain; avoid hype.
