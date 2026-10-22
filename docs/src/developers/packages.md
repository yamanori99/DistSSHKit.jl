# Packages

This page is the list the release rules read. Adding a package is one
row here, plus the checks in [Releasing](releasing.md).

Release in dependency order: a package after everything it depends on.
Wait until General merges each release before the next. Today that is
DistSSHRun, then DistSSHQueue, then DistSSHKit.

| Package | Depends on | Reexports | Installed on its own | Compat files | Ordinary path | Before register |
| --- | --- | --- | --- | --- | --- | --- |
| DistSSHRun | — | — | yes | — | `setup`, `go`, `ride`, `drive` | required checks, the PR's Linux E2E, and on a version-cut pull request `Downstream SSH E2E (DistSSHQueue, 1.13)`. Do not register while that job is red; open a DistSSHQueue issue when the cause is DistSSHQueue. Do not wait for E2E weekly. No open `cut-hold` |
| DistSSHQueue | DistSSHRun | — | yes | `Project.toml`, `test/Project.toml` | FIFO enqueue, `serve` | required checks and the PR's Linux E2E. Do not wait for E2E weekly. No open `cut-hold` |
| DistSSHKit | DistSSHRun, DistSSHQueue | DistSSHRun, DistSSHQueue | yes (main entry) | `Project.toml`, `test/Project.toml`, `docs/Project.toml` | ordinary `~/` roots, default `drive` / `go` / `setup` | `Pkg.test` 1.13 on Ubuntu and macOS; JETLS; Aqua; Documenter; Gitleaks; PR label. WSL2 1.13 is a main push and CI weekly, not the pull request gate. Do not wait on DistSSHRun's E2E |

`testenv/example-job/Project.toml` in DistSSHQueue pins DistSSHRun at
`"0.1.2"`. Raise that floor only when an older DistSSHRun lacks a fix
that example promises. It is not part of every Queue cut.

DistSSHKit's required checks are the ones named in the table.
A version-cut pull request runs the full suite. Path filters do not
apply. A main push that only raises `version` and updates `NEWS.md`
does not re-run Test. Register from the green pull request.

`cut-hold` is on DistSSHRun and DistSSHQueue. A red Linux job in a
scheduled E2E weekly run (daily) adds it to the Issue `E2E weekly
failed`. Intel and WSL do not. A later green scheduled Linux removes it,
even if Intel or WSL is still red. The Issue stays open until a whole
run is green.
DistSSHKit has no `cut-hold`.

When a package breaks something public, every package that reexports it
raises its minor too. A package that depends on it without reexporting
raises only its compat, in a patch, unless the change leaks into its own
public API. A change in an upper package never raises a lower one.

A breaking release of a package that many others depend on is a release
of all of them together. Keep that package small. Today `DistSSHBase` and
`DistSSHUp` are submodules of DistSSHRun (`DistSSHRun.DistSSHBase` and
`DistSSHRun.DistSSHUp`), not separate packages. DistSSHQueue and
DistSSHKit use those submodules. If they are later split out and
registered, DistSSHUp would depend on DistSSHBase and be installed on its
own. DistSSHKit would depend on both and reexport neither. Both would
start at 0.1.0. Add the row before the first release.

Rules for 1.0 are not decided.
