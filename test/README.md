# Tests

How this repo tests DistSSHKit. Maintainer checklist:
[CONTRIBUTING.md](../CONTRIBUTING.md).

## How to run

From this checkout's root:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

That is `test/runtests.jl`, which includes the files under Layout:
public reexports and `julia -m DistSSHKit` routing.
`reexport.jl` pins the names Kit exports. If that test fails after a
DistSSHRun or DistSSHQueue release and Kit itself did not change, read the
new name. Update the set in a Kit patch when the increase is intended.
Tests for a job
started on this machine live in DistSSHRun.
Tests for jobs left on a machine that stays on live in DistSSHQueue.
Aqua is a separate CI job, not `Pkg.test()`.
`Pkg.test()` on this checkout is not the PkgEval sandbox. Real SSH is
DistSSHRun's E2E, not this repo. Reproduce that sandbox:
[PkgEval](#pkgeval).

## Layout

```text
test/
  runtests.jl      # Pkg.test() — include only
  helpers.jl       # _main_capture, _with_fake_ssh, _kit_proc
  reexport.jl      # public names; pinned export set
  routing.jl       # main wording, streams, and the _route table
  consistency.jl   # command lists
  hop.jl           # qhost: PATH ssh, no real connection
  version.jl       # Project.toml version text
  state.jl         # CLI entry and env
  subprocess.jl    # child exit codes
  ssh_opts.jl      # DISTRIBUTED_SSH_OPTS
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
  (the files under [Layout](#layout)). Ubuntu, `macos-latest`, and WSL2 Ubuntu.
  All three are required checks.
- **unit / integration / SSH E2E**: a job started on this machine, in
  DistSSHRun. Not this repo's `Pkg.test()`.
- **doctests** (~5 s): `src/` docstring examples (Documenter, Julia 1.13).
  Not workers / SSH.

## Compile bench

`bench/compile/measure.jl` records precompile time, `using` time, CLI wall time, the size of `src/**/*.jl` (file count, physical lines, non-blank lines, bytes), and the host (OS name, arch, CPU). CI weekly runs it on Julia 1.13 and 1.14-nightly, and so does a `main` push that raises `Project.toml` `version`. A `main` run appends the result to the `bench-data` branch and rebuilds that branch's README. A command that exits nonzero stops the run before a sample is written. Other runs upload the result as an artifact and do not push. A sample is flagged when, against the previous sample on the same Julia slot, the host OS or arch changes, package precompile grows by 1.5x and 0.5s, a command wall grows by 1.5x and 1s, or a method of at least 200 ms is new in the top 20 or doubles. The job is `continue-on-error` and does not fail the weekly notify.

```bash
julia --startup-file=no --project=. bench/compile/measure.jl --out /tmp/compile-bench.toml --slot local
```

## PkgEval

[PkgEval](https://github.com/JuliaCI/PkgEval.jl) runs the daily ecosystem
check. The sandbox is Debian bookworm without `tzdata`, with
`LANG=C.UTF-8`, a pipe for stdout, and a 45 minute test limit. Daily uses
the General tarball. This recipe mounts this checkout read-only, and
dependencies resolve from General, so an unreleased DistSSHRun or
DistSSHQueue change is not in the sandbox. This package:
<https://juliaci.github.io/NanosoldierReports/pkgeval_badges/D/DistSSHKit.html>
Latest ecosystem report:
<https://juliaci.github.io/NanosoldierReports/pkgeval_badges/report.html>
Run it on Linux with cgroup v2 and unprivileged user namespaces, before a
General cut. The host Julia is 1.12 or newer. PkgEval is not in General,
so this adds it from its repository. The tested Julia is nightly.
CI: `PkgEval (nightly, ubuntu-latest, x64)` on **main** and a version-cut
PR (`continue-on-error`; not a required check). Not ordinary PRs.

From this checkout:

```bash
julia -e '
  using Pkg
  Pkg.activate(temp=true)
  Pkg.add(url="https://github.com/JuliaCI/PkgEval.jl")
  using PkgEval
  config = Configuration(; julia="nightly")
  pkg = Package(; name="DistSSHKit", url="/package")
  result = PkgEval.evaluate_package(config, pkg; echo=true,
      mounts=Dict("/package:ro" => pwd()))
  exit(result.status == :test ? 0 : 1)
'
```

## Writing tests

1. Meta-package checks go in the files under [Layout](#layout).
   `test/runtests.jl` only includes them. Unit, integration, and SSH
   tests for a job started on this machine go in DistSSHRun. Tests for
   jobs left on a machine that stays on go in DistSSHQueue.
2. Do not add an SSH suite here. `Pkg.test` must not start Docker.
3. Short Oracle / non-guarantee comment at the top of the file.

CLI also honors `DISTSSHKIT_QUIET`, `DISTSSHKIT_PROGRESS`,
`DISTSSHKIT_VERBOSE`, `DISTSSHKIT_YES`, `DISTSSHKIT_HOSTS`,
`DISTSSHKIT_HOSTS_FILE` (DistSSHRun `src/DistSSHRun/argv/session.jl`).

## Aqua

CI and [`.github/aqua-check.sh`](../.github/aqua-check.sh) `Pkg.add("Aqua")`
with no version pin.
