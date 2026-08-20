# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- Shared `KitRunResult` (`ok`, `kind`, `output_dir`, `log_dir`, `failed_step`,
  `exit_code`) plus `kit_run_result` / `report_run_errors`.
  `DriveResult` and `PipelineResult` now carry `output_dir` / `failed_step`
  (and `PipelineResult.exit_code`). `DriveResult(ok, code)` still works.
  `output_dir` / `log_dir` reflect the directory actually used (same
  resolution `drive` uses for `Results:` / its log file), not just an
  explicitly-passed `output_dir=` / `log_dir=` keyword.
- `execute!(kind, script, tokens; …)::KitRunResult`, `kind ∈ (:go, :drive)`:
  one seam over `go!` / `drive!` for callers that pick the kind at runtime
  (thin wrapper; `go!` / `drive!` are unchanged).
- Public worker-token API for `local:N` / `host:N`: `parse_worker_tokens`,
  `ParsedWorkerTokens`, `worker_tokens_fully_specified`,
  `remote_hosts_from_tokens`, `worker_plan_from_tokens`, plus primitives
  `split_worker_token` / `is_local_host_name`.
- `drive` atexit and `size!` / `measure_rss`: skip `rmprocs` when only the
  driver remains. Lone-master Julia reports `nworkers() == 1` /
  `workers() == [1]`; the old unconditional / `nworkers() > 0` guards called
  `rmprocs([1])` and warned `process 1 not removed`.
  `measure_rss` now `rmprocs`es only the probe pids it added (not the whole
  cluster) and always does so in `finally`.

## 0.3.1

- `go!(…; output_dir=PATH)` sets the batch root (same keyword as `drive!`).
  `collect_spec::String` remains a compat alias; both set is an error.
  `collect_spec=false` still skips collect. CLI `--output-dir` is unchanged.
- Docs: LICENSE carves out Julia dots (CC BY-NC-SA 4.0, Stefan Karpinski)
  from the MIT source license. READMEs, Introduction, and
  `docs/src/assets/README.md` credit
  [julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics).
- Docs: Japanese README (`README.ja.md`). English README and Introduction
  restructured around terms, `go` / `drive`, setup, and rsync vs git.
  Topology diagram is a hand-edited SVG (`docs/src/assets/diagram/topology.svg`);
  bake writes Japanese and dark variants, plus PNG (`bake.jl --png`).
  DocumenterMermaid is gone. READMEs note that `drive` / `size` stay on
  `julia -m DistSSHKit` under the `distsshkit` app.
- Docs: `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL`, and gitignore `.distsshkit/` in
  the job project.
- `setup --sync` / `--pull` (and `go` / `drive` `--sync`, `sync!`,
  `setup!(…, :sync|:pull)`): confirm before git push/pull, same as clone.
  `-y` / `session.yes` skips the prompt.
- Opt-in `drive --require-all-hosts` / `DISTSSHKIT_REQUIRE_ALL_HOSTS` (and
  `drive!(…; require_all_hosts=true)`): fail if a listed SSH host did not join
  or post-run collect reported an error. Default remains best-effort exit 0.
- `DISTSSHKIT_JOBS` (default 1): concurrent rsync hosts, concurrent post-run
  collect hosts, and parallel `detect_julia_path` before sequential `size!`
  `addprocs`. `addprocs` itself stays sequential.

## 0.3.0 (2026-08-16)

Breaking cut after `0.2.1`. No `0.2.2` on General.

- **Breaking:** Julia **1.12+** only (library and CLI). 1.10 / 1.11 dropped.
- **Breaking:** exported `size_plan` removed; use `size!`.
- **Breaking:** `go` / `drive` argv wrappers are no longer exported. Use
  `go!` / `drive!` or `julia -m DistSSHKit`.

- Optional `pkg> app add DistSSHKit` (Pkg Apps, experimental): `distsshkit` on
  PATH. Same argv as `-m`. Prefer for `go` / `setup` / `demo`; `drive` / `size`
  stay `julia --project=. -m DistSSHKit`.

- `setup --runtest`: `Pkg.test()` of the **job** project on remotes (after
  `--check`; not DistSSHKit's own `Pkg.test()`).

- **Breaking:** `demo install` copies one family (`with_kit` or `without_kit`),
  not both. Bare `demo install` refuses. API: `install_demos(; family=...)`.

- Confirm prompts always print (`-q` / `--progress` included). `-y` still skips
  them.

- CLI job root: `julia -m DistSSHKit` from a project that depends on DistSSHKit
  uses that project's `Project.toml`, not the kit's.
  `DISTRIBUTED_PROJECT_ROOT` overrides.

## 0.2.1 (2026-08-14)

Patch after the first General registration (`0.2.0`).

- Library / `go!` / `drive!`: Julia **1.10+**. Terminal `julia -m DistSSHKit`: **1.12+**.
- `setup!` (same modes as CLI `setup`). `size!` (alias of `size_plan`).
- `go` / `drive` / `setup` / `size` share `--hosts` and `DISTSSHKIT_HOSTS`.
- Failures that need a next command: diagnose, then explain for CLI vs API.
- `drive` collect works with remote `~` roots.
- Controllers: macOS, Linux, and WSL2 Ubuntu (not native Windows).

## 0.2.0 (2026-08-11)

First release on General.
