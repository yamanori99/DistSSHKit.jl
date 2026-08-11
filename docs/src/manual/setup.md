# [setup](@id Manual-setup)

Prepare SSH hosts before [`go`](@ref Manual-go) / [`drive`](@ref Manual-drive).

```bash
julia --project=. -m DistSSHKit setup [options] HOST...
```

From Julia, the same prep is [`sync!`](@ref) then [`instantiate!`](@ref)
([API](@ref API), [First Steps · Prepare](@ref Tutorial-Prepare)).

Also: [Requirements](@ref), `setup --help`. Flag vocabulary: [User Guide](@ref Manual).

## Flags

Pick **one mode** per invocation (except shared options).

| Flag | Meaning |
| --- | --- |
| `--check` | Verify SSH, Julia, project files, deps; git commit parity when remotes have `.git/` |
| `--clone` | `git clone` onto each remote at an empty/missing path |
| `--rsync` | Rsync local tree onto missing/empty path (recommended first deploy; no remote `.git/`) |
| `--sync` | Local `git push`, then `git pull` on remotes (git workflows) |
| `--pull` | `git pull` on laptop first, then remotes (no push) |
| `--instantiate` | `Pkg.instantiate` on remotes after deploy |
| `--cleanup` | Kill stale Julia worker processes (local + remotes) |
| `--delete` | Remove remote project dirs (destructive; confirm unless `-y`) |
| `--repo URL` | Clone URL (default: local `origin`) |
| `--remote-path PATH` | Remote repo root (alias `--remote-dir`; or `DISTRIBUTED_REMOTE_PROJECT_ROOT`) |
| `--julia PATH` | Julia on remotes (default: auto / `JULIA_DISTRIBUTED_EXE`) |
| `--ignore-julia-version` | Warn instead of fail on major.minor mismatch |
| `-q` / `--quiet` | Hide terminal detail; kit log under `.distsshkit/setup/` still written |
| `--progress` | Thin phase bar (not with `-q`) |
| `-y` / `--yes` | Accept confirmation prompts non-interactively |
| `--hosts-file PATH` | Append SSH hosts (`host:N` → host name only) |
| `-v` / `--version` | Print DistSSHKit version and exit |
| `-h` / `--help` | Full help |

`--clone` / `--rsync` never overwrite a nonempty remote path; use `--delete`
first to replace.

## Remote path

Default: `~/Parent/RepoName` from the local tree. Override with
`--remote-path` or `DISTRIBUTED_REMOTE_PROJECT_ROOT` (same ENV for `go` /
`drive`).

## After `--rsync`

No remote `.git/` — that is fine. `go` / `drive` do not pre-run sync or
require git parity by default. Kit logs: `<project>/.distsshkit/setup/`.
