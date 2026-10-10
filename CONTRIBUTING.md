# Contributing

Internals of this repo.

- Users:
  [stable docs](https://yamanori99.github.io/DistSSHKit.jl/stable/)
  (`docs/`), [README.md](README.md), [README.ja.md](README.ja.md),
  [NEWS.md](NEWS.md), [HISTORY.md](HISTORY.md)
- Dev docs: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/)

## Scope

Users add this package and do three things: start a job on this machine,
put the same Julia channel on each machine (`up`), or leave jobs on a
machine that stays on. The first two are implemented in
[DistSSHRun.jl](https://github.com/yamanori99/DistSSHRun.jl).
Jobs left on a machine that stays on are implemented in
[DistSSHQueue.jl](https://github.com/yamanori99/DistSSHQueue.jl).

Happy-path bugs (ordinary `~/` roots, default `drive` / `go` / `setup`);
CI / Julia slots / Aqua / JETLS / Runic drift. Enhancement Issue first, then a PR.

Windows and GPU-package help stay on the horizon
([Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26)).

Chat: [Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
Tracked bugs stay Issues. Direction for DistSSHKit as a whole is still
[Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26).

## ride and `:effect_free`

`ride` rewrites `map` / `filter` / simple comprehensions and may `pmap`
them. Safety is borrowed from the discussion on
[JuliaLang/julia#43910](https://github.com/JuliaLang/julia/issues/43910)
(`:effect_free` on `f` and `getindex`). That issue is a thread-parallel
POC; `ride` is process/`pmap` (parent or SSH). Do not describe `ride`
as an implementation of that POC in README or contract Discussions.

## Requirements

macOS, Linux, or WSL2 Ubuntu. Not native Windows (DistSSHKit shells out to
`ssh` / `rsync`).

- Library, `Pkg.test()`, `julia -m DistSSHKit`, docs: Julia **1.13+**
- SSH: Git, OpenSSH, rsync. Match remote **major.minor** to the stable
  line in `.github/julia-slots.env` (**1.13**)

Prefer [juliaup](https://github.com/JuliaLang/juliaup). Details:
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/dev/requirements/).

## Setup

```bash
git clone https://github.com/yamanori99/DistSSHKit.jl.git
cd DistSSHKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

From another app (a **separate** env, not a job you rsync):

```bash
julia --project=/path/to/KitDevEnv.jl \
  -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHKit.jl")'
```

Do not `Pkg.develop` DistSSHKit from a project you actually run
distributed jobs from — the Manifest records an absolute path the
workers do not have. Keep a separate environment for that development.
Real jobs `Pkg.add` DistSSHKit from General.

On 1.13+, `julia --project=. -m DistSSHKit …` matches `Pkg.add`.

Main loads only a direct `[deps]` name. Users add DistSSHKit, so `using`
and `julia -m` use DistSSHKit when that name is in `[deps]`. Otherwise
they use DistSSHRun or DistSSHQueue, the package that owns the work.
Do not tell users to `pkg> add` the inner package so Main can see it.
The same sentence sits next to DistSSHRun `_detached_m_package` and
DistSSHQueue `m_package`.

## Test

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run this on **1.13** (and **1.14-nightly** if you have it).
Layout: [test/README.md](test/README.md).

Checkout `Pkg.test()` is not a Registry tarball. After changing those
gates (smokes, demo copy, `ssh` / `git` spawn, probe), and before a
General cut, run the disposable copy in
[test/README.md](test/README.md#registry-tree). CI runs that shape on
**main** and a version-cut PR (slot tip; not a required check). Not on
ordinary PRs.

Smoke (1.13+; copies land in `distsshkit_demos/`):

```bash
dest=$(mktemp -d)
julia --project=. -m DistSSHKit demo install with_kit --dest "$dest"
julia --project=. -m DistSSHKit drive parent:2 \
  "$dest/distsshkit_demos/with_kit/square_file.jl"
```

`Pkg.test()` does not run real SSH. SSH coverage is DistSSHRun's E2E.
This repo does not wait on that result to register.

CI uploads Codecov on **main push** only (Ubuntu `Pkg.test` 1.13, flag
`pkgtest`). The `macos-latest` job does not upload. PR `Pkg.test` runs
without coverage instrumentation. Status checks are informational
(`codecov.yml`).

### Julia versions

Versions are lines in
[`.github/julia-slots.env`](.github/julia-slots.env). Write the version
(`1.13`, `1.14-nightly`). The job name uses that same string. Do not add
a second stable line.

- **1.13** (required): `Project.toml` julia floor, the maintained
  stable. Pkg.test on Ubuntu, macOS, and WSL2 Ubuntu, plus Aqua, JETLS,
  Documenter, bake. Codecov `pkgtest` on **main push**, Ubuntu only
- **1.14-nightly** (not required): next-minor nightly. Pkg.test and Aqua
  on Ubuntu, macOS, and WSL2 Ubuntu. `continue-on-error`

This package feels SSH hosts, Pkg, and lockfiles more than a compute-model
library does. When Julia announces that it has stopped maintaining the
previous minor, raise the stable line to the new stable and rename the
jobs. The move from 1.12 to 1.13 is that case (1.12 became unmaintained
when 1.13 shipped). Do not track the LTS for its own sake. Other
situations (a prerelease as the stable line, dropping a minor only for a
language feature, and similar) are decided one by one. Do not move the
stable line to nightly, or to a minor that has only just shipped, as an
automatic rule. A release candidate of the next minor is not a second
required version. **1.14-nightly** is that view until the stable line
moves.

JETLS runs on **1.13**. If that runtime is outside the range JETLS lists,
add another version line and job. No JETLS on nightly.

When the stable line moves to a new **major.minor**, change the job names
and the main ruleset in the same PR.

### PR CI

These run as jobs of the `Test` workflow
([`.github/workflows/CI.yml`](.github/workflows/CI.yml)). Ubuntu:
`Pkg.test` 1.13, JETLS 1.13, Aqua 1.13, Gitleaks (also rejects `< 0.0.1`
in `Project.toml`). macOS (`macos-latest`) and WSL2 Ubuntu 24.04:
`Pkg.test` 1.13, same heavy gate, no coverage upload. Both are required.
Documenter 1.13 is
[`.github/workflows/Documentation.yml`](.github/workflows/Documentation.yml).
Tip `Pkg.test` / Aqua stay on **main**, **CI weekly**, and a version-cut
PR, on Ubuntu, macOS, and WSL2. Registry tree stays on **main** and a
version-cut PR, not ordinary PRs. SSH is DistSSHRun's E2E, not a check
on this repo.

[Runic](https://github.com/fredrikekre/Runic.jl) is a separate light
workflow ([`.github/workflows/runic.yml`](.github/workflows/runic.yml)).
It is not a substitute for `Pkg.test`. Soft on PRs (not in the
required-name list). Monthly cron on `main` opens Issue
`Runic monthly failed` (`alert`) when `--check` is red.

These files **alone** skip the heavy jobs (UI: skipping; Pkg.test on
Ubuntu, macOS, and WSL2, plus JETLS / Aqua, do not start). Documenter
still runs when `docs/**`, README,
`src/**`, or `Project.toml` changed; otherwise it is skipped too.
Allowlisted markdown-only PRs skip the heavy jobs (skipping UI):

- `README.md`, `README.ja.md`, `CONTRIBUTING.md`, `NEWS.md`,
  `HISTORY.md`,
  `SECURITY.md`, `LICENSE`
- `.gitignore`, `.git-blame-ignore-revs`,
  `.github/pull_request_template.md`, `.coderabbit.yaml`
- `docs/**`, and markdown under `test/`

A new root markdown file stays heavy until listed in
[`.github/actions/ci-heavy/action.yml`](.github/actions/ci-heavy/action.yml).
A version increase skips none of this: Pkg.test (Ubuntu, macOS, and WSL2),
JETLS, Aqua, and Documenter all run. Register when the required checks
below are green. Do not wait on DistSSHRun's E2E.

Required to merge (branch protection uses these names). Tip jobs are not
in this list. A job skipped by the heavy gate shows as skipping (not a
green empty run).

- `Pkg.test (1.13, ubuntu-latest, x64)`
- `Pkg.test (1.13, macos-latest, aarch64)`
- `Pkg.test (1.13, WSL2 ubuntu-24.04, x64)`
- `JETLS (1.13, ubuntu-latest, x64)`
- `Aqua (1.13, ubuntu-latest, x64)`
- `Documenter (1.13, ubuntu-latest, x64)`
- `Gitleaks`
- `PR label`

### Local checks

```bash
julia -e 'using Pkg; Pkg.Apps.add("Runic")'   # once
runic --inplace src test   # before push; not `.` (markdown out of scope)
./.github/jetls-check.sh    # hint+; same files as CI (no `--threads=auto`)
./.github/aqua-check.sh     # latest registry Aqua; not part of Pkg.test()
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs --color=yes docs/make.jl
julia docs/src/assets/bake.jl          # optional --png / --gif
gitleaks detect --source .
```

[Runic](https://github.com/fredrikekre/Runic.jl) CI
(`fredrikekre/runic-action@v1`, `version: '1'`) runs `--check` on every
tracked `.jl`. Format `docs/*.jl` too if you change them.
Skip `test/artifacts/**` (no `.jl` there). A Runic minor may make
`--check` red: re-run `runic --inplace src test` and push. Optional:
after a bulk format squash, add the landed SHA to
[`.git-blame-ignore-revs`](.git-blame-ignore-revs) if blame is noisy.
Local blame:

```bash
git config blame.ignoreRevsFile .git-blame-ignore-revs
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

**CI weekly** (Sunday 10:00 JST, or Run workflow): same `Pkg.test` /
JETLS / Aqua as a PR, including `macos-latest` and WSL2 (no coverage).
Not a PR check. Catches 1.13 / Aqua / JETLS `@release` drift when nothing
merged that week. Failure of the 1.13 jobs opens Issue `CI weekly failed`
(`alert`); 1.14-nightly is omitted from that notify.

**Runic monthly** (1st 10:00 JST, or Run workflow): `runic --check` on
tracked `.jl` (`version: '1'`). Not a required PR check. Catches Runic
minor drift when nothing formatted that month. Failure opens Issue
`Runic monthly failed` (`alert`).

## Pull requests

- Branch from `main`. Squash-merge only. Merged heads are deleted.
- One reviewable change per PR. Split unless `main` would be broken in
  between.
- Large plans: Discussion or Enhancement Issue first, then small PRs.

### CodeRabbit (experimental)

Open PRs may get an optional [CodeRabbit](https://docs.coderabbit.ai)
pass. Config is [`.coderabbit.yaml`](.coderabbit.yaml) on the **PR
head** (not a merge gate). JETLS / tests stay the gate. Treat
inline comments as hints; do not apply Autofix or generated tests
unless you want that change. `@coderabbitai pause` / `review` as
needed. Settings will move as we learn what is useful.

`setup --clone` / `--rsync` refuse a non-empty destination. Redeploy
with `setup --delete`. First deploy `--rsync`; later git `--sync` /
`--pull`. Do not weaken that refusal without tests.

## Release

- `breaking`: incompatible behavior. May land **without** a version
  bump. About behavior, not the bump.
- version cut: `Project.toml` `version` went up. CI compares that
  file with the base. Other `Project.toml` edits do not. The PR suite
  does not path-skip. Labels adds `cut` when the version rises above
  the base. Removing it sticks until the next rise. CI still reads the
  file, not the label. Do not lower `version`;
  General never takes a version down.

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

1. Register when the required checks on the version-cut PR are green
   (`Pkg.test` 1.13 on Ubuntu, macOS, and WSL2 Ubuntu, plus JETLS, Aqua,
   Documenter, Gitleaks, PR label). Do not wait on DistSSHRun's E2E.
   Do not lower `version`.
2. Register on the merge commit (not the PR body). Paste the NEWS
   section under `Release notes:`.
3. TagBot tags once General has the release.

TagBot uses SSH deploy key secret `DOCUMENTER_KEY` (write deploy key on
this repo) so the `vX.Y.Z` tag starts Docs and `stable` updates. Docs
still deploy with `GITHUB_TOKEN`. Do not add a `+doc1` tag unless that
path failed. Manual rebuild: `gh workflow run Docs --ref vX.Y.Z`.

GitHub Releases need a token that can `POST /repos/.../releases`
(`Contents: write`). `GITHUB_TOKEN` 403'd on v0.7.1 even though that
SHA did not touch `.github/workflows`. Keep cut commits to
`Project.toml` + `NEWS.md` (no workflow files). For Releases, set
repo secret **`TAGBOT_PAT`**: fine-grained PAT, this repo only,
Contents read/write, Issues read/write. Add Workflows read/write only
when the tagged SHA changes `.github/workflows` (GitHub then requires
it). TagBot reads General with `GITHUB_TOKEN` (`registry_token`); a
this-repo-only PAT 401s on `GET JuliaRegistries/General`. Empty
`TAGBOT_PAT` still falls back to `GITHUB_TOKEN` for `token`. Do not put
`permissions:` on `.github/workflows/TagBot.yml` (TagBot defaults).
If TagBot opens `TagBot: Manual intervention needed for releases`,
the tag may already exist; create the Release only
(`gh release create vX.Y.Z --verify-tag --notes "…"`), then close the
Issue. `--verify-tag` fails if the tag is missing (plain `gh release
create` would mint it from the default branch).

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

**Issues** (Bug / Enhancement forms only): `bug` or `enhancement`. Horizon
(`when:*`) is
**when**, not type or path: every open Issue gets exactly one of
`when:current` / `when:next` / `when:later`. `julia-next` is optional
and orthogonal: Julia tip / next stable Base or stdlib drift (keep
`when:later` until that Julia is the DistSSHKit contract). Usage questions are
Discussions. Confirmed bugs are Issues. `breaking` is a PR label.
Direction:
[Discussion #26](https://github.com/yamanori99/DistSSHKit.jl/discussions/26).
Security: [SECURITY.md](SECURITY.md).

Maintainer memo: [#50](https://github.com/yamanori99/DistSSHKit.jl/issues/50)
is closed (`not_planned` in this repo). Jobs that wait on a machine that stays on live in
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

Path labels are command names only. This repo has no `src/cli/`, so
`gen-labeler.sh` emits no `area:*` rules. `gen-labeler.sh --check` fails
when `labeler.yml` is stale. An empty file is valid. The Labels workflow
does not call `actions/labeler` when there are no rules. `base/` and
`up/` stay unlabeled. This repo's `Pkg.test` is `test/runtests.jl`.
Run-surface tests live in DistSSHRun.

Backfill every PR after a vocabulary change:

```bash
./.github/retag-pr-areas.sh           # dry-run
./.github/retag-pr-areas.sh --apply
```

### Type labels

Every PR needs one of `bug` / `enhancement` / `chore`. Dependabot skips
the type check (`dependencies` only). Override with
`gh pr edit N --add-label …`.

Weekly Dependabot covers `github-actions` and Julia registry deps.
Stdlib names are `ignore` in [`.github/dependabot.yml`](.github/dependabot.yml)
(`Dates`, `Distributed`, `Pkg`, `SHA`, `TOML`, `Test`). A new
third-party `[deps]` entry is picked up with no YAML change; a new
stdlib must be added to that ignore list. Stdlib `[compat]` stays with
the Julia floor. The Julia updater otherwise appends `< 0.0.1` for the
pre-1.10 Pkg.test 0.0.0 sandbox; this package is 1.13 and does not need
that union (comma is or, not and). Scan /
`./.github/pkg-compat-check.sh` rejects that token.

CI infers, in order:

1. A unique type on a closing issue (`Fixes #N`)
2. Else the branch prefix: `feat/` → enhancement, `fix/` → bug,
   `breaking/` → breaking, `chore/` / `docs/` / `ci/` / `test/` /
   anything else → chore

`fix/` plus `Fixes` an enhancement issue gets `enhancement`. `breaking`
may sit next to the type label. After a cut, a human registers when
the required checks are green; TagBot tags.

Ruleset `main` requires check `PR label` (workflow `Type`). Type labels
(`bug` / `enhancement` / `breaking` / `chore`) must exist (`gh label
create` if missing). `when:*` and `julia-next` are Issues only (not a
PR type).

| Kind | Color | Labels |
| --- | --- | --- |
| Type | red / green / yellow / dark red / purple / mint | `bug` `enhancement` `chore` `breaking` `dependencies` |
| Scheduled failure | orange `#ff4d00` | `alert` on bot Issues (`CI weekly failed`, `Runic monthly failed`) |
| Horizon | orange `#fdba74` / violet `#c4b5fd` / slate `#94a3b8` | `when:current` `when:next` `when:later` |
| Julia next | Julia purple `#9558b2` | `julia-next` (Issues: tip / next-stable API; not a PR type) |

| `when:*` | Use |
| --- | --- |
| `when:current` | Broken daily path or CLI that lies; same 0.7 contract |
| `when:next` | Same contract: chrome, copy, colors |
| `when:later` | Later cut: testitem, citation, comparison docs |

## Language

`.jl` comments, docstrings, and errors: English. Install or Docs links:
`docs/src`, [README.md](README.md), and [README.ja.md](README.ja.md).
User-visible behavior: NEWS (date the section when tagged). Generative
AI is allowed; you own the diff. Keep docs plain.
