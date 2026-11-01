# Julia 1.14 / 1.15 impact

Status as of 2026-11-01.

Checked on `main` at DistSSHRun `b4a3520`, DistSSHQueue `de8de4c`, and
DistSSHKit `0494b6e`. The comparison is Julia 1.13.3 against Julia
1.14.0-alpha2.

Julia 1.14 does not break DistSSH. One Queue fix is tracked in
[#497](https://github.com/yamanori99/DistSSHQueue.jl/issues/497). One
item folds into the planned post-transfer hash verification (b1) work
in DistSSHRun 0.2.0. The rest are no-impact or future ideas.

## 1.14-pre CI on main

DistSSHRun: all 1.14-pre jobs are green. That is CI weekly `Pkg.test`
on Ubuntu, macOS, and WSL2, Aqua, and the compile bench, plus `CI.yml`
`Pkg.test`, JETLS, Aqua, and Linux SSH E2E with the parent and the
workers on 1.14. The E2E job is `ssh-e2e-1-14-pre` at `CI.yml:883`.
The only red jobs are the known downstream ones on 1.13.

DistSSHQueue: all 1.14-pre jobs and nightly are green.

DistSSHKit: `CI.yml` on 1.14-pre is green. CI weekly `Pkg.test` is red
on every version, including 1.13, so that is not a 1.14 issue. It is
likely the known compat / `[sources]` red during the 0.2.0-DEV cycle.

## Manifest format 2.2

Low. One Queue todo.

A Manifest resolved on 1.14 gets `manifest_format = "2.2"` and
`environment_id = ... # generated`. Pkg 1.13 (`manifest.jl:220-226`)
only warns when the major version is outside 1-2, so 2.2 reads
silently. New keys land in `other` (`manifest.jl:283-289`).
`is_manifest_current` is true on 1.13.

DistSSHRun's guard already refuses mixed minors:
`src/DistSSHRun/setup/remote_ops.jl:494-503` (minor check) plus
`julia_version_strict=true` at `:505`. Both directions were confirmed.
The unit test is `test/unit/DistSSHRun/setup/instantiate.jl:225-231`.

Gap: Queue `_queue_local_instantiate!`
(`src/DistSSHQueue/queue.jl:584-596`, called at `:690` and `:700`) uses
plain `Pkg.instantiate()`, which only warns on a mixed minor and
continues. Tracked in
[#497](https://github.com/yamanori99/DistSSHQueue.jl/issues/497)
(milestone 0.10.0).

`ship` / `content_tree_hash`: no structural change. The hash changes
once when a 1.14 resolve writes `environment_id`. DistSSHRun never
reads `manifest_format`.

Precompile cache naming (`julia#63310`): the id is added to the project
path. Loading picks any compatible cache file, so per-run
`runs/<id>/src` paths behave as before.

The mixed-version E2E channel is 1.12 (`.github/julia-slots.env`). There
is no 1.13-parent/1.14-worker E2E. The guard reads only
`julia_version`, and the unit tests cover it. No action.

## Pkg#4861 and Pkg#4237

Path and workspace `[sources]`. No impact.

The DistSSHRun root `Project.toml` has no `[sources]`.
`lib/DistSSHBase` and `lib/DistSSHUp` are included via `include`
(`DistSSHRun.jl:118-155`), not deps. `test/Project.toml:11-12` points
at `".."` inside the package.

DistSSHQueue and DistSSHKit `[sources]` are `url/rev = "main"`, not
path, and their test and docs projects repeat the root entries.

Downstream CI uses `Pkg.develop(path=upstream)` (DistSSHRun
`ci-weekly.yml:135`).

## SAT resolver (Pkg#4738)

No impact.

DistSSHRun `src` never resolves, adds, or updates. It only instantiates
from the Manifest. `display.jl:545` `Pkg.resolve()` is hint text.

Resolves only in test environments: DistSSHRun
`testenv/docker-ssh/scripts/up.sh:124` and
`testenv/apple-container-ssh/scripts/up.sh:185`; DistSSHQueue
`testenv/docker-ssh/scripts/up.sh:149-152` and
`testenv/apple-container-ssh/scripts/up.sh:179`; `Pkg.develop` in
`test/support/host.jl:54`. DistSSHQueue `queue.jl:589` resolves only
without a Manifest.

No test depends on a particular resolution. Fallback:
`JULIA_PKG_RESOLVER=maxsum`.

## Base.SignalCondition (julia#63344)

Future idea only. Not in 1.14.0-alpha2 (`isdefined` is false;
`CANCEL_TOKEN` is present).

Current handling: DistSSHBase `sigint.jl:5-50` (`is_sigint`,
`shield_sigint`, `without_cancel`). DistSSHRun stop ladder is SIGINT,
then SIGTERM, then SIGKILL (`execute.jl:1240-1300`,
`drive/types.jl:281-301`). `atexit(_flush_go_slot_pmap_items!)` is at
`provenance.jl:572`. DistSSHQueue `serve` stops by SIGTERM
(`store.jl:654-696`, `qhost/serve.jl:70-143`) and handles SIGINT
(`queue.jl:1188-1231`).

Idea: observe SIGTERM to flush provenance and record termination, and
let `serve` shut down in order, instead of relying on `atexit`. Nothing
to do now. SIGKILL and power loss remain unhandled by design.

## uuid5 (1.15)

No impact. No `uuid5` or `UUIDs` usage in any of the three repos.

## julia#63511, #64034, #64076

No changes needed. All three help.

- `julia#63511`: DistSSHRun `pkill` patterns `julia.*--worker` and
  `julia.*--bind-to` (`remote.jl:4`, `:13-55`) do not catch precompile
  workers. Before 1.14 those could be orphaned on an SSH drop during
  instantiate. On 1.14 they exit with the parent.
- `julia#64034`: DistSSHRun uses Distributed `addprocs`
  (`launch.jl:351`, `:383`; `size/measure.jl:117`, `:179`). Worker
  loading by `PkgId` gets faster. Marked for a 1.13 backport.
- `julia#64076`: cache files stay readable when the source tree is
  replaced. Marked for a 1.13 backport.

## compat-overrides, lazy, add --from, update_on_mismatch

No impact.

Do not use `update_on_mismatch` for job environments. It would silently
update and defeat DistSSHRun's no-remote-resolve design.
`[compat-overrides]` could later let downstream jobs test against
DistSSHRun DEV, only once 1.14 is the minimum. `lazy` and `--from` do
not apply.

## Post-transfer hash verification (b1)

DistSSHRun 0.2.0 post-transfer hash verification.

The Tar stdlib changed between 1.13 (`10e4e96`) and 1.14 (`1ea3c30`),
29 commits, including `tree_hash` refactors (`5dcaa406`, `f3425c55`)
and a stricter Windows path check on extract (`f106eec6`).

Tested: `Tar.tree_hash` of the DistSSHRun tree is identical on both
versions, for GNU tar and for `Tar.create` output. Both versions
produced byte-identical tars.

Recommendation: add a cross-minor `Tar.tree_hash` parity test
(1.13 <-> 1.14) to b1's done-when.

## Follow-ups

- [ ] DistSSHQueue
  [#497](https://github.com/yamanori99/DistSSHQueue.jl/issues/497)
- [ ] b1 parity test
- [ ] Revisit `SignalCondition` when it lands
