# Contributing

How to work on this repository. End-user usage: [Documenter](https://yamanori99.github.io/DistSSHKit.jl/stable/) (`docs/`) and [README.md](README.md). Dev docs: [dev](https://yamanori99.github.io/DistSSHKit.jl/dev/).

## Requirements

- macOS and Linux
- Julia 1.12+ (test locally on `1.12` and `~1.13.0-0` when available)
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
- Solo dev: push to `main` directly is fine. Before sharing or tagging, run `Pkg.test()` locally on Julia 1.12+ (and `~1.13.0-0` when available).
- Breaking changes (CLI names, module name, driver contract `init_output_dir!` / `main`, …): bump `x` in `Project.toml` `0.x.y`. Patch `y` only for non-breaking changes.
- Tags (`vX.Y.Z`) after merge are a maintainer decision (`git tag -a vX.Y.Z`). TagBot.yml is unused until a General-registry release.

Remote safety: `setup --clone` / `--rsync` refuse a non-empty destination; redeploy needs `setup --delete` first. Recommended first deploy is `setup --rsync`; git updates use `setup --sync` / `--pull`. Do not weaken nonempty-path refusal without reason and tests.

## Before a release or sharing

Required:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Recommended smoke (same as [`demos/README.md`](demos/README.md)):

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit drive local:2 demos/with_kit/square_file.jl
```

Remote SSH / sync / worker changes: run **SSH E2E** locally when paths match.
Locally (including macOS controllers): `testenv/docker-ssh/scripts/up.sh --e2e` (see [`testenv/docker-ssh/README.md`](testenv/docker-ssh/README.md)). Optional Mac-only workers (not CI): [`testenv/apple-container-ssh`](testenv/apple-container-ssh).

Optional static analysis (install [jetls](https://github.com/JuliaLang/jetls.jl) locally):

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

Logo / social edits under `docs/src/assets/`: run `julia docs/src/assets/bake.jl` (plus `--png` / `--gif` for rasters).

Optional secret scan ([gitleaks](https://github.com/gitleaks/gitleaks); e.g. `brew install gitleaks`):

```bash
gitleaks detect --source .
```

## Errors: diagnose then explain

For user-facing failures that need a recovery tip (especially when CLI and bang API
should suggest different next commands):

1. **Diagnose** — return facts only (`kind`, paths, …). No finished English prose.
2. **Explain** — format for `surface=:cli` or `surface=:api` (command wording only).

Layout:

- Shared surface helpers and builders: `src/DistSSHKit/explain.jl`
- `KitCliSession.hint_surface` / `hint_surface(session)` carry the entry surface
- Domain diagnose/explain: next to the domain (`demos.jl` for demo-install tips)

Builders in `explain.jl` today:

- `explain_script_not_found` / `explain_pipeline_driver_missing`
- `explain_hosts_file_not_found` / `explain_hosts_file_empty` / `explain_no_hosts`
- `explain_clone_repo_required` / `explain_clone_origin_missing`
- `explain_size_probe_not_found`

Wiring:

| Entry | Surface |
| --- | --- |
| CLI (`drive` / `go` / `setup` / `size`) | `:cli` (default `KitCliSession`) |
| `KitSession` / bang APIs | `:api` (set in `KitSession` constructor) |
| `drive!` | `hint_surface(session)` on parsed args |
| `go!` | `hint_surface=` (default `:api`; CLI passes `:cli`) |
| `pipeline!` / `sync!` / `collect!` / `setup!` / `size_plan` | `hint_surface(session)` |

Parse-only `ArgumentError`s (bad flags, typoes) may stay as plain strings. Prefer
diagnose + explain when adding tip-bearing failures. Do **not** grow a large
issue/remedy type hierarchy until several domains share the same shape.

## Language and AI

- `.jl` sources (comments, docstrings, errors): English
- User-facing docs: update `docs/src/*.md` and [README.md](README.md) when install or Docs links change
- Generative AI is allowed. Understand and verify what you submit. Keep docs plain; avoid hype.
