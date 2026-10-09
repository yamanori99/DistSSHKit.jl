# Tests

How this repo tests DistSSHKit. Maintainer checklist:
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Run

From the kit checkout root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl`: public reexports and `julia -m DistSSHKit`
routing. The run-surface suite lives in DistSSHRun. The queue suite lives
in DistSSHQueue. Aqua is a separate CI job, not `Pkg.test()`.
`Pkg.test()` must pass on a Registry install (no kit `Manifest.toml`, often
mode 444). Real SSH is DistSSHRun's E2E, not this repo. Occasional copy
recipe: [Registry tree](#registry-tree).

## Layout

```text
test/
  runtests.jl     # Pkg.test() — reexports and CLI routing
  Project.toml
```

In-process unit tests and child-julia integration tests live in
DistSSHRun (`test/unit/`, `test/integration/`). DistSSHQueue has its own
suite. This checkout does not keep those trees.

## Layers

Green on one layer does not imply the others. Child CLI uses
`julia -m DistSSHKit`.

- **JETLS** (~25 s): types / hints on entry files. Not runtime.
- **Aqua** (~5 s): ambiguities, exports, compat (latest registry Aqua).
  Not CLI / workers.
- **Pkg.test**: reexports and `julia -m DistSSHKit` routing
  (`test/runtests.jl`). Ubuntu and `macos-latest`. The macOS job is not
  a required check.
- **unit / integration / SSH E2E**: DistSSHRun. Not this repo's
  `Pkg.test()`.
- **doctests** (~5 s): `src/` docstring examples (Documenter, Julia 1.13).
  Not workers / SSH.

## Registry tree

[PkgEval](https://github.com/JuliaCI/PkgEval.jl) (via
[Nanosoldier](https://github.com/JuliaCI/Nanosoldier.jl)) and `Pkg.add` use
a Registry tarball, not this checkout. This package:
<https://juliaci.github.io/NanosoldierReports/pkgeval_badges/D/DistSSHKit.html>
Latest ecosystem report:
<https://juliaci.github.io/NanosoldierReports/pkgeval_badges/report.html>
Reproduce that tree: copy without kit `.git` / `Manifest.toml`, `Pkg.add`
from a **bare** `file://` git (so the installed package dir has no `.git` —
DistSSHKit talks to git for jobs, not for its own install), `chmod a-w` on
`pkgdir`, then `Pkg.test`. Do this after changing the gates above, and
before a General cut. CI: `Pkg.test - registry tree` on **main** and
a version-cut PR (slot tip, no `ssh`; not a required check). Not
ordinary PRs.

Copy without `Manifest.toml` (and without `.git`). On Linux, `mktemp -d` is
enough.

```bash
WORKDIR=$(mktemp -d "$HOME/dsk.XXXXXX")
rsync -a \
  --exclude .git \
  --exclude Manifest.toml \
  --exclude docs/Manifest.toml \
  --exclude docs/build \
  --exclude test/artifacts \
  ./ "$WORKDIR/"
```

This machine (**1.13**, and `+nightly`). Distro `ssh` / `git` stay on `PATH`.
On Linux this is enough for the tree; it does not reproduce a missing
`ssh`. Do not `git init` inside the copy (that would put `.git` on the kit
tree). Use a bare repo, then `Pkg.add(; url=)`.

```bash
BARE=$(mktemp -d "$HOME/dsk.git.XXXXXX")
git init --bare -q "$BARE"
git --git-dir="$BARE" --work-tree="$WORKDIR" add -A
git --git-dir="$BARE" --work-tree="$WORKDIR" \
  -c user.email=ci@distsshkit -c user.name=ci commit -q -m tree
```

```bash
julia -e '
  using Pkg
  Pkg.activate(temp=true)
  Pkg.add(; url=ARGS[1])
  using DistSSHKit
  run(Cmd(["chmod", "-R", "a-w", pkgdir(DistSSHKit)]))
  Pkg.test("DistSSHKit")
' "file://$BARE"
```

Linux without `ssh`: same [juliaup](https://github.com/JuliaLang/juliaup)
Ubuntu container from macOS or from Linux
([Docker Hub `julia`](https://hub.docker.com/_/julia) has no `nightly`
tag). `--no-install-recommends` keeps `openssh-client` out.

```bash
docker run --rm \
  -v "$WORKDIR:/pkg:ro" \
  ubuntu:24.04 \
  bash -lc "
    apt-get update -qq &&
    apt-get install -y -qq --no-install-recommends \
      curl ca-certificates git &&
    curl -fsSL https://install.julialang.org |
      sh -s -- --yes --default-channel nightly &&
    export PATH=\"\$HOME/.juliaup/bin:\$PATH\" &&
    cp -a /pkg /tmp/dsk &&
    git init --bare -q /tmp/dsk.git &&
    git --git-dir=/tmp/dsk.git --work-tree=/tmp/dsk add -A &&
    git --git-dir=/tmp/dsk.git --work-tree=/tmp/dsk \
      -c user.email=ci@distsshkit -c user.name=ci \
      commit -q -m tree &&
    julia +nightly -e '
      using Pkg
      Pkg.activate(temp=true)
      Pkg.add(; url=\"file:///tmp/dsk.git\")
      using DistSSHKit
      run(Cmd([\"chmod\", \"-R\", \"a-w\", pkgdir(DistSSHKit)]))
      Pkg.test(\"DistSSHKit\")
    '
  "
```

## Writing tests

1. Meta-package checks go in `test/runtests.jl`. Run-surface unit,
   integration, and SSH tests go in DistSSHRun. Queue tests go in
   DistSSHQueue.
2. Do not add an SSH suite here. `Pkg.test` must not start Docker.
3. Short Oracle / non-guarantee comment at the top of the file.

CLI also honors `DISTSSHKIT_QUIET`, `DISTSSHKIT_PROGRESS`,
`DISTSSHKIT_VERBOSE`, `DISTSSHKIT_YES`, `DISTSSHKIT_HOSTS`,
`DISTSSHKIT_HOSTS_FILE` (DistSSHRun `src/DistSSHRun/argv/session.jl`).

## Aqua

CI and [`.github/aqua-check.sh`](../.github/aqua-check.sh) `Pkg.add("Aqua")`
with no version pin.
