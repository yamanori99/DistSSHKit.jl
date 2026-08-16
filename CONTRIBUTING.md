# Contributing

Internals of this repo. Users: [stable docs](https://yamanori99.github.io/DistSSHKit.jl/stable/) (`docs/`), [README.md](README.md), [NEWS.md](NEWS.md). Dev: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/).

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (the kit shells out to `ssh` / `rsync`).

- Library and `Pkg.test()`: Julia **1.10+**
- `julia -m DistSSHKit` and docs: **1.12+** (`~1.13.0-0` when that channel exists)
- SSH: Git, OpenSSH, rsync. Match remote **major.minor** (CI workers are 1.12)

Prefer [juliaup](https://github.com/JuliaLang/juliaup). Details: [Requirements](https://yamanori99.github.io/DistSSHKit.jl/dev/requirements/).

## Setup

```bash
git clone https://github.com/yamanori99/DistSSHKit.jl.git
cd DistSSHKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

From another app:

```bash
julia --project=/path/to/MyProject.jl -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHKit.jl")'
```

On 1.12+, `julia --project=. -m DistSSHKit …` matches `Pkg.add`. On 1.10–1.11 use `go!` / `drive!` or [`main`](https://yamanori99.github.io/DistSSHKit.jl/stable/api/).

## Test

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Do this on 1.10, and on 1.12 / 1.13 when you can. Layout: [test/README.md](test/README.md).

Smoke (1.12+; [`demos/README.md`](demos/README.md)):

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
```

`Pkg.test()` does not run real SSH. That is `test/e2e.jl`:

```bash
testenv/docker-ssh/scripts/up.sh --e2e
```

CI E2E (`DISTSSHKIT_CODE_COVERAGE=1`) writes `.cov` and uploads to Codecov (merged with `Pkg.test`). Local coverage:

```bash
DISTSSHKIT_CODE_COVERAGE=1 testenv/docker-ssh/scripts/up.sh --e2e
```

See [testenv/docker-ssh/README.md](testenv/docker-ssh/README.md). Skip the image build with `DISTSSHKIT_WORKER_IMAGE=ghcr.io/yamanori99/distsshkit-linux-ssh-worker:latest`. Mac-only workers (not CI): [testenv/apple-container-ssh](testenv/apple-container-ssh).

### PR CI

Ubuntu: `Pkg.test` (1.10–1.13), JETLS, Aqua, Documenter (1.12), Gitleaks. Linux E2E runs if `src/`, `test/`, `demos/`, `testenv/`, `Project.toml`, or the E2E workflow changed.

These files alone skip the heavy steps (job still starts; Pkg.test / JETLS / Aqua / Documenter do not run): `README.md`, `CONTRIBUTING.md`, `NEWS.md`, `SECURITY.md`, `LICENSE`, `.gitignore`, `.github/pull_request_template.md`. A new root markdown file stays heavy until listed in [`.github/actions/ci-heavy/action.yml`](.github/actions/ci-heavy/action.yml). Changes under `docs/src` still run those jobs.

### Local

```bash
./.github/jetls-check.sh    # hint+; same files as CI
./.github/aqua-check.sh     # latest registry Aqua; not part of Pkg.test()
```

JETLS CI uses `aviatesk/JETLS.jl/.github/actions/check@release` (moving tag). After a bump, re-read [cli-check](https://aviatesk.github.io/JETLS.jl/dev/cli-check/) and keep failing on hint+.

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs --color=yes docs/make.jl
julia docs/src/assets/bake.jl          # optional --png / --gif
gitleaks detect --source .
```

JETLS is the type gate. Do not commit `.vscode/settings.json` to silence the Language Server.

[Fatou](https://fatou.dev) is local only. Do not add `fatou.toml` or Fatou to `.vscode/extensions.json`. After a Fatou bump, check it did not rewrite files you did not mean to touch.

### Daily E2E

04:00 JST or Run workflow `E2E daily`: `ubuntu-latest`, `macos-15-intel`, and WSL2 against `ubuntu-24.04`. Not a PR check. A failed run opens (or comments on) Issue `E2E daily failed`; a later green run closes it.

### Weekly CI

Sunday 10:00 JST or Run workflow `CI weekly`: same `Pkg.test` / JETLS / Aqua matrix as a PR (no coverage). Not a PR check. Catches Julia 1.13 / Aqua / JETLS `@release` drift when nothing merged that week. Failure opens Issue `CI weekly failed` (`ci`).

## Workflow

Branch from `main`. Squash-merge only. One reviewable change per PR; split unless `main` would be broken in between. Large plans: Discussion or Enhancement Issue first, then small PRs. Merged heads are deleted.

`setup --clone` / `--rsync` refuse a non-empty destination. Redeploy with `setup --delete`. First deploy `--rsync`; later git `--sync` / `--pull`. Do not weaken that refusal without tests.

### Release

- `breaking`: incompatible behavior. Can land without a version bump.
- `cut`: `Project.toml` `version` went up. CI adds this; other `Project.toml` edits do not.
- On a breaking line bump `x` in `0.x.y`; otherwise bump `y`.
- After merge: `@JuliaRegistrator register`, and paste the [NEWS.md](NEWS.md) section under `Release notes:`. TagBot tags once General has the release. Date NEWS `YYYY-MM-DD` UTC on the tag day.
- Repo Settings → Actions → Workflow permissions: **Read and write** (`GITHUB_TOKEN`).

## Errors

CLI and bang APIs often need different next commands.

1. Diagnose — facts (`kind`, paths). No prose.
2. Explain — `surface=:cli` or `:api` (command wording only).

Helpers: `src/DistSSHKit/explain.jl`. Surface is `hint_surface(session)`. Keep domain tips next to the domain (`demos.jl` for demo-install). Parse-only `ArgumentError`s can stay plain strings. Do not add an issue/remedy type hierarchy until several domains share a shape.

## Issues and Discussions

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. The area dropdown is triage; add `area:*` if useful. Usage questions are Discussions. Confirmed bugs are Issues. `breaking` and `cut` are PR labels. Direction: [Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26). Security: [SECURITY.md](SECURITY.md).

**Discussions**: Q&A, Ideas (promote to an Enhancement Issue when tracking), General, Show and tell, Polls, Announcements. Registry cuts do not need an Announcements post; the GitHub Release is enough.

## Labels

```bash
./.github/gen-labeler.sh          # rewrite
./.github/gen-labeler.sh --check  # CI drift
```

- `src/cli/<area>/` → `area:<area>` (`explain` / `demos` too)
- `test/**` except `test/unit/` and `test/integration/` → `area:test`
- Product tests under those two trees keep only their `area:<area>`
- `.github/**` → `ci`
- No `area:kit`

New CLI area or a new product-test tree: edit the script, regenerate, create the GitHub label.

Every PR needs one type label (`bug` / `enhancement` / `chore`). CI infers, in order: a unique type on a closing issue (`Fixes #N`); else the branch prefix (`feat/` → enhancement, `fix/` → bug, `breaking/` → breaking, `chore/` / `docs/` / `ci/` / `test/` / anything else → chore). `fix/` plus `Fixes` an enhancement issue gets `enhancement`. Override with `gh pr edit N --add-label …`. Dependabot skips the type check (`dependencies` only).

`breaking` may sit next to the type label. It is about behavior, not the version bump. After merge a human registers; TagBot tags.

## Language

`.jl` comments, docstrings, and errors: English. Install or Docs links: `docs/src` and README. User-visible behavior: NEWS (date the section when tagged). Generative AI is allowed; you own the diff. Keep docs plain.
