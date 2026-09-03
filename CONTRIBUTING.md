# Contributing

Internals of this repo.

- Users:
  [stable docs](https://yamanori99.github.io/DistSSHKit.jl/stable/)
  (`docs/`), [README.md](README.md), [README.ja.md](README.ja.md),
  [NEWS.md](NEWS.md)
- Dev docs: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/)

## Scope

This repo is one run (`go` / `drive` / `setup` and the bang APIs). Jobs
that wait in line are
[DistSSHQueue.jl](https://github.com/yamanori99/DistSSHQueue.jl).

Happy-path bugs (ordinary `~/` roots, default `drive` / `go` / `setup`);
CI / Julia slots / Aqua / JETLS drift. Enhancement Issue first, then a PR.

**Does not land here:** a job queue, or `schedule`, inside Kit.
Windows and GPU-package help stay on the horizon
([Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26)).

Chat: [Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
Tracked bugs stay Issues. Direction for the kit as a whole is still
[Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26).

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (the kit shells out to
`ssh` / `rsync`).

- Library, `Pkg.test()`, `julia -m DistSSHKit`, docs: Julia **1.12+**
- SSH: Git, OpenSSH, rsync. Match remote **major.minor** (E2E workers =
  slot **max**)

Prefer [juliaup](https://github.com/JuliaLang/juliaup). Details:
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/dev/requirements/).

## Setup

```bash
git clone https://github.com/yamanori99/DistSSHKit.jl.git
cd DistSSHKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

From another app:

```bash
julia --project=/path/to/MyProject.jl \
  -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHKit.jl")'
```

On 1.12+, `julia --project=. -m DistSSHKit …` matches `Pkg.add`.

## Test

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run this on slot **min** and **max** (and **tip** if you have nightly).
Layout: [test/README.md](test/README.md).

Checkout `Pkg.test()` is not a Registry tarball. After changing those
gates (smokes, demo copy, `ssh` / `git` spawn, probe), and before a
General cut, run the disposable copy in
[test/README.md](test/README.md#registry-tree). CI runs that shape on
**main** and **cut** (slot tip; not a required check). Not on ordinary
PRs.

Smoke (1.12+; [demos/README.md](demos/README.md)):

```bash
dest=$(mktemp -d)
julia --project=. -m DistSSHKit demo install with_kit --dest "$dest"
julia --project=. -m DistSSHKit drive parent:2 \
  "$dest/distsshkit_demos/with_kit/square_file.jl"
```

`Pkg.test()` does not run real SSH. That is `test/e2e.jl`:

```bash
testenv/docker-ssh/scripts/up.sh --e2e
```

CI uploads Codecov on **main push** only (`Pkg.test` max slot, flag
`pkgtest`). PR `Pkg.test` runs without coverage instrumentation. E2E
coverage (flag `e2e`) runs on **E2E weekly** and **`cut` PR** E2E — not
on ordinary PR E2E. Local coverage:

```bash
DISTSSHKIT_CODE_COVERAGE=1 \
  testenv/docker-ssh/scripts/up.sh --e2e
```

See [testenv/docker-ssh/README.md](testenv/docker-ssh/README.md). Skip
the image build with
`DISTSSHKIT_WORKER_IMAGE=ghcr.io/yamanori99/distsshkit-linux-ssh-worker:latest`.
Apple silicon, no Docker:
[testenv/apple-container-ssh](testenv/apple-container-ssh)
(`./scripts/up.sh --e2e`; same `test/e2e.jl`).

### Julia slots

Exactly three pins, in
[`.github/julia-slots.env`](.github/julia-slots.env). Do not add a
fourth version job. Slide the pin; keep job names `min` / `max` /
`tip`.

- **min** (required): `Project.toml` julia floor. Pkg.test (no
  coverage), Aqua, JETLS, Documenter, bake
- **max** (required): newest tagged or prerelease (`versions.json`).
  Pkg.test, Aqua, **main** / weekly / `cut` E2E, GHCR worker. Codecov
  `pkgtest` on **main push** only
- **tip** (not required): next-minor nightly. Pkg.test, Aqua.
  `continue-on-error`

JETLS is min plus `JULIA_SLOT_JETLS_MAX` (job name still `JETLS -
max`). That pin lags when `max` / `tip` move past what JETLS lists
(today 1.12.2–1.13). Raise it only after JETLS supports that runtime.
No JETLS **tip**.

When a new RC lands, change `JULIA_SLOT_MAX` only. If that RC is a new
**major.minor**, bump the worker Dockerfile / WSL `--default-channel`
in the same PR (E2E pair). When bumping compat, raise `JULIA_SLOT_MIN`
only.

### PR CI

These run as jobs of the `Test` workflow
([`.github/workflows/CI.yml`](.github/workflows/CI.yml)). Ubuntu:
`Pkg.test` min / max, JETLS min / max, Aqua min / max, Documenter min,
Gitleaks. Linux E2E (max) does **not** run on an ordinary PR. It runs
on **main** push (path filter minus markdown under `test/` / `demos/` /
`testenv/`), **`cut`**, **E2E weekly**, and `workflow_dispatch`. Tip
`Pkg.test` / Aqua stay on **main**, **CI weekly**, and `cut`. Registry
tree stays on **main** and `cut` (ci-cut), not ordinary PRs.

These files **alone** skip the heavy steps (job still starts; Pkg.test /
JETLS / Aqua do not run). Documenter still runs when `docs/**`, README,
`src/**`, or `Project.toml` changed:

- `README.md`, `README.ja.md`, `CONTRIBUTING.md`, `NEWS.md`,
  `SECURITY.md`, `LICENSE`
- `.gitignore`, `.github/pull_request_template.md`, `.coderabbit.yaml`
- `docs/**`, and markdown under `test/` / `demos/` / `testenv/`

A new root markdown file stays heavy until listed in
[`.github/actions/ci-heavy/action.yml`](.github/actions/ci-heavy/action.yml).
A `cut` label skips none of this: Pkg.test, JETLS, Aqua, Documenter,
and Linux E2E all run. macOS / WSL stay on `E2E weekly`, not the PR.
Register only after that matrix is green on the merge commit.

Required to merge (branch protection uses these names). Tip jobs are
allow-failure. A skipped heavy step still leaves the job green.

- `Pkg.test - min - ubuntu-latest`
- `Pkg.test - max - ubuntu-latest`
- `JETLS - min - ubuntu-latest`
- `JETLS - max - ubuntu-latest`
- `Aqua - min - ubuntu-latest`
- `Aqua - max - ubuntu-latest`
- `Documenter - min - ubuntu-latest`
- `Gitleaks`
- `ubuntu-latest → ubuntu-24.04`
- `PR label`

### Local checks

```bash
./.github/jetls-check.sh    # hint+; same files as CI
./.github/aqua-check.sh     # latest registry Aqua; not part of Pkg.test()
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs --color=yes docs/make.jl
julia docs/src/assets/bake.jl          # optional --png / --gif
gitleaks detect --source .
```

JETLS CI uses
[`.github/actions/jetls-check`](.github/actions/jetls-check/action.yml)
(installs `JETLS.jl` `@release` after `julia-actions/cache`). After a
bump, re-read
[cli-check](https://aviatesk.github.io/JETLS.jl/dev/cli-check/) and keep
failing on hint+.

JETLS is the type gate. Do not commit `.vscode/settings.json` to
silence the Language Server.

[Fatou](https://fatou.dev) is local only. Do not add `fatou.toml` or
Fatou to `.vscode/extensions.json`. After a Fatou bump, check it did
not rewrite files you did not mean to touch.

### Scheduled CI

**E2E weekly** (Sunday 04:00 JST, or Run workflow): `ubuntu-latest`,
`macos-15-intel`, WSL2 → `ubuntu-24.04`. Linux job uploads E2E Codecov.
Not a PR check. Failure opens (or comments on) Issue `E2E weekly
failed`; a later green run closes it. After a `cut` merge, dispatch
this on that commit and wait for green before register. While weekly
is red (or you pause), put `cut-hold` on that Issue — see Release.

**CI weekly** (Sunday 10:00 JST, or Run workflow): same `Pkg.test` /
JETLS / Aqua slots as a PR (no coverage). Not a PR check. Catches max /
Aqua / JETLS `@release` drift when nothing merged that week. Failure of
min/max jobs opens Issue `CI weekly failed` (`ci`); tip is omitted from
that notify.

## Pull requests

- Branch from `main`. Squash-merge only. Merged heads are deleted.
- One reviewable change per PR. Split unless `main` would be broken in
  between.
- Large plans: Discussion or Enhancement Issue first, then small PRs.

### CodeRabbit (experimental)

Open PRs may get an optional [CodeRabbit](https://docs.coderabbit.ai)
pass. Config is [`.coderabbit.yaml`](.coderabbit.yaml) on the **PR
head** (not a merge gate). JETLS / tests / e2e stay the gate. Treat
inline comments as hints; do not apply Autofix or generated tests
unless you want that change. `@coderabbitai pause` / `review` as
needed. Settings will move as we learn what is useful.

`setup --clone` / `--rsync` refuse a non-empty destination. Redeploy
with `setup --delete`. First deploy `--rsync`; later git `--sync` /
`--pull`. Do not weaken that refusal without tests.

## Release

- `breaking`: incompatible behavior. May land **without** a version
  bump. About behavior, not the bump.
- `cut`: `Project.toml` `version` went up. CI adds this; other
  `Project.toml` edits do not. The PR suite does not path-skip.
- `cut-hold`: after a `cut` merge, postpone register (E2E weekly red,
  or you pause). Manual Issue label — not a PR check. Do not lower
  `version`; General never takes a version down.

On a breaking line bump `x` in `0.x.y`; otherwise bump `y`.

### When to cut

Not a calendar. Cut when [NEWS.md](NEWS.md) **Unreleased** has something
General users should get. Do not ship an empty cut. Do not automate the
bump or `@JuliaRegistrator register`.

- Happy-path bug (ordinary `~/` roots, default `drive` / `go` /
  `setup`): yes, that patch promptly
- Opt-in flags, docs, CI, labels, internal cache: when someone needs it
  on General, **or** those items have sat in Unreleased for **two
  weeks**

Cut happy-path bugs promptly. Opt-in flags, docs, and CI follow the
two-week rule above unless a General user needs them sooner.

### After a cut merges

1. Run **E2E weekly** on the **merge commit**
   (`gh workflow run "E2E weekly" --ref <sha>`). Do not register until
   Linux, macOS Intel, and WSL are green. Ordinary PRs skip Linux E2E;
   `cut` and this dispatch cover it. A same-day green run on that SHA
   is enough; do not wait for the Sunday cron if you dispatched.
2. If weekly is red (or you pause): put `cut-hold` on the tracking
   Issue (`E2E weekly failed`, or a short cut-hold Issue). Do not
   `@JuliaRegistrator register` while `cut-hold` is open. Do not
   lower `version`.
3. Green again: remove `cut-hold`, then register on that merge commit
   (not the PR body). Paste the NEWS section under `Release notes:`.
4. Skip that version on General instead: keep `cut-hold` until a later
   cut (higher `version`) is ready, then register that later cut.
5. TagBot tags once General has the release.

TagBot uses SSH deploy key secret `DOCUMENTER_KEY` (write deploy key on
this repo) so the `vX.Y.Z` tag starts Docs and `stable` updates. Docs
still deploy with `GITHUB_TOKEN`. Do not add a `+doc1` tag unless that
path failed. Manual rebuild: `gh workflow run Docs --ref vX.Y.Z`.

Repo Settings → Actions → Workflow permissions: **Read and write**
(`GITHUB_TOKEN`).

## Errors

CLI and bang APIs often need different next commands.

1. Diagnose — facts (`kind`, paths). No prose.
2. Explain — `surface=:cli` or `:api` (command wording only).

Helpers: `src/DistSSHKit/explain.jl`. Surface is
`hint_surface(session)`. Keep domain tips next to the domain
(`demos.jl` for demo-install). Parse-only `ArgumentError`s can stay
plain strings. Do not add an issue/remedy type hierarchy until several
domains share a shape.

## Issues and Discussions

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. The
area dropdown is triage; add `area:*` if useful. Usage questions are
Discussions. Confirmed bugs are Issues. `breaking` and `cut` are PR
labels; `cut-hold` is an Issue label after a cut merge. Direction:
[Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26).
Security: [SECURITY.md](SECURITY.md).

Maintainer memo: [#50](https://github.com/yamanori99/DistSSHKit.jl/issues/50)
is closed (`not_planned` in-kit). The hall is
[DistSSHQueue.jl](https://github.com/yamanori99/DistSSHQueue.jl)
(General). Do not add `schedule` here.

**Discussions**: Q&A, Ideas (promote to an Enhancement Issue when
tracking), General, Show and tell, Polls, Announcements. Registry cuts
do not need an Announcements post; the GitHub Release is enough.

## Labels

```bash
./.github/gen-labeler.sh          # rewrite
./.github/gen-labeler.sh --check  # CI drift
```

Every tracked path must match some `area:*` glob (`gen-labeler.sh
--check`). Globs are positive paths; do not add `!` excludes (labeler
ORs them as "not this path" and tags unrelated files). Path labeler
syncs only `area:*`. After `setLabels` it restores type / `cut` / other
non-area labels so a concurrent Type job is not wiped.

- `src/cli/<area>/` (`explain` / `demos` too): `area:<area>`
- Shared kit (`src/DistSSHKit.jl`, leftover DistSSHKit / argv stems,
  matching unit tests, shared `test/*/cli/` files, package meta):
  `area:kit`
- Harness under `test/` (not `unit/` / `integration/`) and
  `testenv/**`: `area:test`
- `test/e2e.jl`, `test/support/ssh_e2e.jl`: CLI areas `drive` / `go` /
  `setup` / `size` as well
- Product tests under `unit/` and `integration/`: that `area:<area>`
  (plus `area:kit` when leftover shared kit)
- `docs/**`: `area:docs`
- `README.md`, `README.ja.md`, `NEWS.md`, `CONTRIBUTING.md`,
  `SECURITY.md`: `area:project-docs`
- `.github/**`, `codecov.yml`, `.coderabbit.yaml`: `area:ci`

New CLI area or a new product-test tree: edit the script, regenerate,
create the GitHub label.

Backfill every PR after a vocabulary change:

```bash
./.github/retag-pr-areas.sh           # dry-run
./.github/retag-pr-areas.sh --apply
```

### Type labels

Every PR needs one of `bug` / `enhancement` / `chore`. Dependabot skips
the type check (`dependencies` only). Override with
`gh pr edit N --add-label …`.

CI infers, in order:

1. A unique type on a closing issue (`Fixes #N`)
2. Else the branch prefix: `feat/` → enhancement, `fix/` → bug,
   `breaking/` → breaking, `chore/` / `docs/` / `ci/` / `test/` /
   anything else → chore

`fix/` plus `Fixes` an enhancement issue gets `enhancement`. `breaking`
may sit next to the type label. After merge a human registers, or
holds with `cut-hold`; TagBot tags.

## Language

`.jl` comments, docstrings, and errors: English. Install or Docs links:
`docs/src`, [README.md](README.md), and [README.ja.md](README.ja.md).
User-visible behavior: NEWS (date the section when tagged). Generative
AI is allowed; you own the diff. Keep docs plain.
