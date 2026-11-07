# Julia 1.14 / 1.15 impact

Checked against Julia 1.13.3 and Julia 1.14.0-alpha2.

Julia 1.14 does not break DistSSH. One Queue fix is
yamanori99/DistSSHQueue.jl#497. One item belongs with the planned
post-transfer hash verification (b1). The rest are no-impact or later
ideas.

## 1.14-pre CI

DistSSHRun CI weekly runs `Pkg.test` on Ubuntu, macOS, and WSL2, plus
Aqua and the compile bench. `CI.yml` runs `Pkg.test`, JETLS, Aqua, and
Linux SSH E2E. The E2E job is `ssh-e2e-1-14-pre`, with the parent and
the workers on 1.14. Downstream jobs in that workflow run on 1.13.

DistSSHQueue CI runs 1.14-pre jobs and nightly jobs.

DistSSHKit `CI.yml` runs on 1.14-pre. CI weekly `Pkg.test` runs on
each configured Julia, including 1.13 and 1.14-pre.

## Manifest format 2.2

Low. Tracked in yamanori99/DistSSHQueue.jl#497.

A Manifest resolved on 1.14 gets `manifest_format = "2.2"` and
`environment_id = ... # generated`. Pkg 1.13 warns only when the
manifest format major is outside 1-2, so 2.2 loads without that
warning. Unknown keys land in `other`. `Pkg.is_manifest_current` is
true on 1.13.

`_instantiate_remote_e` refuses a Manifest whose `julia_version` minor
differs from the worker (`Base.thisminor`), then instantiates with
`julia_version_strict=true`. Both directions were confirmed. The unit
test is the julia minor mismatch case in
`test/unit/DistSSHRun/setup/instantiate.jl`.

`_queue_local_instantiate!` calls `Pkg.instantiate()` with no
`julia_version_strict`. That warns on a mixed minor and continues.
`_queue_kit_setup!` calls it. Tracked in
yamanori99/DistSSHQueue.jl#497.

`ship` / `content_tree_hash`: no structural change. The hash changes
once when a 1.14 resolve writes `environment_id`. DistSSHRun never
reads `manifest_format`.

Precompile cache naming (JuliaLang/julia#63310): the id is added to
the project path. Loading picks any compatible cache file, so per-run
`runs/<id>/src` paths behave as before.

The mixed-version E2E channel is 1.12 (`.github/julia-slots.env`).
There is no 1.13-parent / 1.14-worker E2E. The guard reads only
`julia_version`, and the unit tests cover it. No action.

## JuliaLang/Pkg.jl#4861 and JuliaLang/Pkg.jl#4237

Path and workspace `[sources]`. No impact.

The DistSSHRun root `Project.toml` has no `[sources]`.
`lib/DistSSHBase` and `lib/DistSSHUp` are included via `include` from
`DistSSHRun.jl`, not as deps. `test/Project.toml` points at `".."`
inside the package.

DistSSHQueue and DistSSHKit `[sources]` are `url` / `rev = "main"`,
not path. Their test and docs projects repeat the root entries.

Downstream CI uses `Pkg.develop(path=upstream)` (DistSSHRun
`ci-weekly.yml`).

## SAT resolver (JuliaLang/Pkg.jl#4738)

No impact.

DistSSHRun `src` never resolves, adds, or updates. It only
instantiates from the Manifest. `missing_manifest_message` prints a
`Pkg.resolve()` hint and does not run it.

Resolves only in test environments: DistSSHRun
`testenv/docker-ssh/scripts/up.sh` and
`testenv/apple-container-ssh/scripts/up.sh`; DistSSHQueue
`testenv/docker-ssh/scripts/up.sh` and
`testenv/apple-container-ssh/scripts/up.sh`; `Pkg.develop` in
DistSSHRun `test/support/host.jl`. `_queue_local_instantiate!`
resolves only when the project has no Manifest.

No test depends on a particular resolution. Fallback:
`JULIA_PKG_RESOLVER=maxsum`.

## Base.SignalCondition

Follow-up idea only. Separate from b1.

Not in Julia 1.14.0-alpha2 (`isdefined(Base, :SignalCondition)` is
false; `CANCEL_TOKEN` is present). JuliaLang/julia#64506 carries
JuliaLang/julia#63344's `Base.SignalCondition`. Revisit if it lands
in a 1.14 release.

Handling: DistSSHBase `is_sigint`, `shield_sigint`, and
`without_cancel` (`sigint.jl`). DistSSHRun `_signal_ladder!` sends
SIGINT, then SIGTERM, then SIGKILL. DistSSHQueue `stop_serve!`
(`store.jl`) stops `serve` by SIGTERM. `serve!` (`queue.jl`) handles
SIGINT. The CLI stop path is `qhost/serve.jl`.

Idea: observe SIGTERM to flush provenance and record termination, and
let `serve` shut down in order. SIGKILL and power loss remain
unhandled by design.

## uuid5 (1.15)

No impact. No `uuid5` or `UUIDs` usage in DistSSHRun, DistSSHQueue, or
DistSSHKit.

## JuliaLang/julia#63511, JuliaLang/julia#64034, JuliaLang/julia#64076

No changes needed. All three help.

- JuliaLang/julia#63511: DistSSHRun `pkill` patterns `julia.*--worker`
  and `julia.*--bind-to` (`JULIA_WORKER_PKILL_PATTERNS` in
  `remote.jl`) do not match precompile workers. Before 1.14 those
  workers could be orphaned when SSH dropped during instantiate. On
  1.14 they exit with the parent.
- JuliaLang/julia#64034: DistSSHRun uses Distributed `addprocs`
  (`size/measure.jl`). Worker loading by `PkgId` gets faster.
- JuliaLang/julia#64076: cache files stay readable when the source
  tree is replaced.

## compat-overrides, lazy, add --from, update_on_mismatch

No impact.

Do not use `update_on_mismatch` for job environments. It would
silently update and defeat DistSSHRun's no-remote-resolve design.
`[compat-overrides]` could later let downstream jobs test against
DistSSHRun DEV, only once 1.14 is the minimum. `lazy` and `--from` do
not apply.

## Post-transfer hash verification (b1)

The Tar stdlib changed between Julia 1.13 and Julia 1.14, including
`tree_hash` refactors and a stricter Windows path check on extract.

`Tar.tree_hash` of the DistSSHRun tree matched on both versions, for
GNU tar and for `Tar.create` output. Both versions produced
byte-identical tars.

Add a cross-minor `Tar.tree_hash` parity test (1.13 and 1.14) to b1's
done-when.

## Follow-ups

- yamanori99/DistSSHQueue.jl#497
- b1: cross-minor `Tar.tree_hash` parity test (1.13 and 1.14)
- Revisit `Base.SignalCondition` if JuliaLang/julia#64506 lands in a
  1.14 release
