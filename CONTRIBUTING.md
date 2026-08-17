# Contributing

Internals of this repo. Users: [stable docs](https://yamanori99.github.io/DistSSHKit.jl/stable/) (`docs/`), [README.md](README.md), [NEWS.md](NEWS.md). Dev: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/).

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (the kit shells out to `ssh` / `rsync`).

- Library, `Pkg.test()`, `julia -m DistSSHKit`, and docs: Julia **1.12+**
- SSH: Git, OpenSSH, rsync. Match remote **major.minor** (E2E workers = slot **min**)

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

On 1.12+, `julia --project=. -m DistSSHKit …` matches `Pkg.add`.

## Test

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Do this on slot **min** and **max** (and **tip** if you have nightly). Layout: [test/README.md](test/README.md).

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

### Julia slots

Exactly three pins, in [`.github/julia-slots.env`](.github/julia-slots.env). Do not add a fourth version job. Slide the pin; keep job names `min` / `max` / `tip`.

| Slot | Role | Required |
| --- | --- | --- |
| **min** | `Project.toml` julia floor. Pkg.test, Aqua, JETLS, Documenter, bake, PR E2E, GHCR worker | yes |
| **max** | Newest tagged or prerelease (`versions.json`). Pkg.test, Aqua | yes |
| **tip** | Next-minor nightly. Pkg.test, Aqua. `continue-on-error` | no |

JETLS is min plus `JULIA_SLOT_JETLS_MAX` (job name still `JETLS - max`). That pin lags when `max` / `tip` move past what JETLS lists (today 1.12.2–1.13). Raise it only after JETLS supports that runtime. No JETLS **tip**.

When a new RC lands, change `JULIA_SLOT_MAX` only. When bumping compat, raise `JULIA_SLOT_MIN` (and the worker Dockerfile / WSL `--default-channel`) in the same PR.

### PR CI

Ubuntu: `Pkg.test` min / max / tip, JETLS min / max, Aqua min / max / tip, Documenter min, Gitleaks. Linux E2E (min) runs if `src/`, `test/`, `demos/`, `testenv/`, `Project.toml`, or the E2E workflow changed.

These files alone skip the heavy steps (job still starts; Pkg.test / JETLS / Aqua / Documenter do not run): `README.md`, `CONTRIBUTING.md`, `NEWS.md`, `SECURITY.md`, `LICENSE`, `.gitignore`, `.github/pull_request_template.md`. A new root markdown file stays heavy until listed in [`.github/actions/ci-heavy/action.yml`](.github/actions/ci-heavy/action.yml). Changes under `docs/src` still run those jobs. A `cut` label skips none of this: Pkg.test, JETLS, Aqua, Documenter, and Linux E2E all run. macOS / WSL stay on `E2E daily`, not the PR.

Required to merge (full job names): `Pkg.test - min - ubuntu-latest`, `Pkg.test - max - ubuntu-latest`, `JETLS - min - ubuntu-latest`, `JETLS - max - ubuntu-latest`, `Aqua - min - ubuntu-latest`, `Aqua - max - ubuntu-latest`, `Documenter - min - ubuntu-latest`, `Gitleaks`, `ubuntu-latest → ubuntu-24.04`, `PR label`. Tip jobs are allow-failure. A skipped heavy step still leaves the job green.

**Once:** GitHub required checks used `Pkg.test - Julia 1.12 - ubuntu-latest` style names. After this lands, set protection to the slot names above.

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

Sunday 10:00 JST or Run workflow `CI weekly`: same `Pkg.test` / JETLS / Aqua slots as a PR (no coverage). Not a PR check. Catches max / Aqua / JETLS `@release` drift when nothing merged that week. Failure of min/max jobs opens Issue `CI weekly failed` (`ci`); tip is omitted from that notify.

## Workflow

Branch from `main`. Squash-merge only. One reviewable change per PR; split unless `main` would be broken in between. Large plans: Discussion or Enhancement Issue first, then small PRs. Merged heads are deleted.

`setup --clone` / `--rsync` refuse a non-empty destination. Redeploy with `setup --delete`. First deploy `--rsync`; later git `--sync` / `--pull`. Do not weaken that refusal without tests.

### Release

- `breaking`: incompatible behavior. Can land without a version bump.
- `cut`: `Project.toml` `version` went up. CI adds this; other `Project.toml` edits do not. The PR suite does not path-skip (see PR CI).
- On a breaking line bump `x` in `0.x.y`; otherwise bump `y`.
- After merge: `@JuliaRegistrator register` on the **merge commit** (not the PR body), and paste the [NEWS.md](NEWS.md) section under `Release notes:`. TagBot tags once General has the release. Date NEWS `YYYY-MM-DD` UTC on the tag day.
- TagBot uses SSH deploy key secret `DOCUMENTER_KEY` (write deploy key on this repo) so the `vX.Y.Z` tag starts Docs and `stable` updates. Docs still deploy with `GITHUB_TOKEN`. Do not add a `+doc1` tag unless that path failed. Manual rebuild: `gh workflow run Docs --ref vX.Y.Z`.
- Repo Settings → Actions → Workflow permissions: **Read and write** (`GITHUB_TOKEN`).

## Errors

CLI and bang APIs often need different next commands.

1. Diagnose — facts (`kind`, paths). No prose.
2. Explain — `surface=:cli` or `:api` (command wording only).

Helpers: `src/DistSSHKit/explain.jl`. Surface is `hint_surface(session)`. Keep domain tips next to the domain (`demos.jl` for demo-install). Parse-only `ArgumentError`s can stay plain strings. Do not add an issue/remedy type hierarchy until several domains share a shape.

## Issues and Discussions

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. The area dropdown is triage; add `area:*` if useful. Usage questions are Discussions. Confirmed bugs are Issues. `breaking` and `cut` are PR labels. Direction: [Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26). Security: [SECURITY.md](SECURITY.md).

Maintainer memo: [#50](https://github.com/yamanori99/DistSSHKit.jl/issues/50) is closed (`not_planned` in-kit). The hall is [DistSSHKitQueue.jl](https://github.com/yamanori99/DistSSHKitQueue.jl) (private for now). Do not add `schedule` here.

**Discussions**: Q&A, Ideas (promote to an Enhancement Issue when tracking), General, Show and tell, Polls, Announcements. Registry cuts do not need an Announcements post; the GitHub Release is enough.

## Labels

```bash
./.github/gen-labeler.sh          # rewrite
./.github/gen-labeler.sh --check  # CI drift
```

- `src/cli/<area>/` → `area:<area>` (`explain` / `demos` too)
- Harness under `test/` (not `unit/` / `integration/`) and `testenv/**` →
  `area:test`. Globs are positive paths from `gen-labeler.sh`; do not add `!`
  excludes (labeler ORs them and tags unrelated files).
- `test/e2e.jl` and `test/support/ssh_e2e.jl` also get CLI areas (`drive` / `go` / `setup` / `size`)
- Product tests under `unit/` and `integration/` keep only their `area:<area>`
- `docs/**`, `README.md`, `NEWS.md`, `demos/**/*.md` → `docs` (not `CONTRIBUTING.md`)
- `.github/**` → `ci`
- No `area:kit`

New CLI area or a new product-test tree: edit the script, regenerate, create the GitHub label.

Every PR needs one type label (`bug` / `enhancement` / `chore`). CI infers, in order: a unique type on a closing issue (`Fixes #N`); else the branch prefix (`feat/` → enhancement, `fix/` → bug, `breaking/` → breaking, `chore/` / `docs/` / `ci/` / `test/` / anything else → chore). `fix/` plus `Fixes` an enhancement issue gets `enhancement`. Override with `gh pr edit N --add-label …`. Dependabot skips the type check (`dependencies` only).

`breaking` may sit next to the type label. It is about behavior, not the version bump. After merge a human registers; TagBot tags.

## Language

`.jl` comments, docstrings, and errors: English. Install or Docs links: `docs/src` and README. User-visible behavior: NEWS (date the section when tagged). Generative AI is allowed; you own the diff. Keep docs plain.
