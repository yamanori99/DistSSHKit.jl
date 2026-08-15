# News

User-facing changes. Date a section `YYYY-MM-DD` (UTC) when that version is tagged.
GitHub Releases may copy these sections (`Release notes:` on `@JuliaRegistrator register`).

## Unreleased

- Optional Pkg Apps entry (Julia **1.12+**): `pkg> app add DistSSHKit` installs
  a `distsshkit` shim. Same dispatcher as `julia -m DistSSHKit`. The default
  install remains `pkg> add`. Drive / size still belong on
  `julia --project=. -m DistSSHKit`.

- `setup --runtest`: `Pkg.test()` of the **job** project on remotes (after
  `--check`; not DistSSHKit's own `Pkg.test()`).

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
