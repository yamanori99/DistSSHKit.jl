# Contributing

How to work on this repository. End-user usage: [Documenter](https://yamanori99.github.io/DistSSHKit.jl/stable/) (`docs/`) and [README.md](README.md). Dev docs: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/).

## Requirements

- macOS and Linux
- Julia 1.12+ (CI: `1.12` and `~1.13.0-0`)
- For SSH-related changes: Git, OpenSSH (`ssh`), rsync; Julia 1.12+ on each remote

The kit shells out to `ssh` / `rsync` / POSIX tools. Remotes: macOS and Linux.

## Setup

```bash
git clone https://github.com/yamanori99/DistSSHKit.jl.git
cd DistSSHKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

To edit the kit while using it from another app:

```bash
julia --project=/path/to/MyProject.jl -e 'using Pkg; Pkg.develop(path="/path/to/DistSSHKit.jl")'
```

Then call `julia --project=. -m DistSSHKit …` from that app the same way as after `Pkg.add`.

## Workflow

- Branch from `main` (`feature/…`, `fix/…`, `docs/…`, `chore/…`).
- **`main` is protected:** open a PR (CI `test (1.12)` and `test (~1.13.0-0)` must pass). Approving review is optional. Do not push to `main` directly.
- Open a PR and fill [the template](.github/pull_request_template.md).
- Breaking changes (CLI names, module name, driver contract `init_output_dir!` / `main`, …): bump `x` in `Project.toml` `0.x.y`. Patch `y` only for non-breaking changes.
- Tags (`vX.Y.Z`) after merge are a maintainer decision (`git tag -a vX.Y.Z`). TagBot.yml is unused until a General-registry release.

Remote safety: `setup --clone` / `--rsync` refuse a non-empty destination; redeploy needs `setup --delete` first. Recommended first deploy is `setup --rsync`; git updates use `setup --sync` / `--pull`. Do not weaken nonempty-path refusal without reason and tests.

## Before opening a PR

Required:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Recommended smoke (same as [`demos/README.md`](demos/README.md)):

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
```

Remote SSH / sync / worker changes: CI runs **SSH E2E** (`linux-to-linux`) when paths match.
Locally (including macOS controllers): `testenv/docker-ssh/scripts/up.sh --e2e` (see [`testenv/docker-ssh/README.md`](testenv/docker-ssh/README.md)). Optional Mac-only workers (not CI): [`testenv/apple-container-ssh`](testenv/apple-container-ssh).

Static analysis runs on every PR via [`.github/workflows/jetls.yml`](.github/workflows/jetls.yml)
(keep the file list there in sync with the command below). The job **fails on
warning or error** (`--exit-severity=warning`). Info-only diagnostics do not fail
the job, but still show as a Checks annotation and in the job Summary. Aim for
zero diagnostics. jetls is not a branch-protection required check yet.

```bash
jetls --threads=auto -- check --exit-severity=warning --progress=none \
  demos/with_kit/*.jl demos/without_kit/*.jl \
  src/DistSSHKit.jl src/cli/go.jl src/cli/drive.jl src/cli/setup.jl src/cli/size.jl \
  test/runtests.jl test/aqua.jl test/fixtures/*.jl
```

Optional docs build:

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs --color=yes docs/make.jl
```

Logo / social edits under `docs/src/assets/`: run `julia docs/src/assets/bake.jl` (plus `--png` / `--gif` for rasters). CI **Assets bake** fails if SVG derivatives drift, and warns if PNG/GIF look stale vs sources.

Optional secret scan ([gitleaks](https://github.com/gitleaks/gitleaks); e.g. `brew install gitleaks`). CI also runs [`.github/workflows/gitleaks.yml`](.github/workflows/gitleaks.yml) on PRs / `main`:

```bash
gitleaks detect --source .
```

Merge needs `CI` green (and `SSH E2E` when it runs). `jetls` (warning+),
`gitleaks`, and Assets bake also run on PRs; merge gating follows branch
protection (currently the `test (…)` jobs). `Pkg.test()` covers bundled demos;
remote SSH is **SSH E2E** only.

## Language and AI

- `.jl` sources (comments, docstrings, errors): English
- User-facing docs: update `docs/src/*.md` and [README.md](README.md) when install or Docs links change
- Generative AI is allowed. Understand and verify what you submit. Keep docs plain; avoid hype.
