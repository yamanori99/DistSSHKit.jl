# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

## 0.3.0

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
