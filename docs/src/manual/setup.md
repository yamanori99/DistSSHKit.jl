# [setup](@id Manual-setup)

Prepare SSH hosts before [`go`](@ref Manual-go) / [`drive`](@ref Manual-drive).

```bash
julia --project=. -m DistSSHKit setup [options] HOST...
```

From Julia, use [`setup!`](@ref) for the same modes as this CLI
(`:delete`, `:rsync`, `:clone`, `:instantiate`, `:check`, `:runtest`, …), or the shorter
[`sync!`](@ref) / [`instantiate!`](@ref) aliases
([API](@ref API), [First Steps · Prepare](@ref Tutorial-Prepare)).
`setup!(session, :clone)` requires an explicit `repo=` URL (clone runs on the remote).

Also: [Requirements](@ref), `setup --help`. Flag vocabulary: [User Guide](@ref Manual).

## rsync or git?

- **`--rsync`** — just sends your local files as-is; no git needed on the
  remote. Good for a first try or a one-off run.
- **`--clone` then `--sync`** — manages the remote as a git repository. Better
  if you're updating the code continuously, or you want
  [`drive --require-git`](@ref Manual-drive) to confirm the remote commit
  matches your local one for reproducibility.

## Flags

Pick **one mode** per invocation (except shared options).

| Flag | Meaning |
| --- | --- |
| `--check` | Verify SSH, Julia, project files, deps; git commit parity when remotes have `.git/` |
| `--clone` | `git clone` onto each remote at an empty/missing path (confirm unless `-y`) |
| `--rsync` | Rsync local tree onto missing/empty path (recommended first deploy; no remote `.git/`; confirm unless `-y`) |
| `--sync` | Local `git push`, then `git pull` on remotes (git workflows; confirm unless `-y`) |
| `--pull` | `git pull` on laptop first, then remotes (no push; confirm unless `-y`) |
| `--instantiate` | `Pkg.instantiate` on remotes after deploy |
| `--runtest` | `Pkg.test()` of the **job** project on remotes (not DistSSHKit's tests) |
| `--cleanup` | Kill stale Julia worker processes (local + remotes); `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1` skips the `pkill` |
| `--delete` | Remove remote project dirs (destructive; confirm unless `-y`) |
| `--repo URL` | Clone URL (default: local `origin`) |
| `--remote-path PATH` | Remote repo root (alias `--remote-dir`; or `DISTRIBUTED_REMOTE_PROJECT_ROOT`) |
| `--julia PATH` | Julia on remotes (default: auto / `JULIA_DISTRIBUTED_EXE`) |
| `--ignore-julia-version` | Warn instead of fail on major.minor mismatch |
| `-q` / `--quiet` | Hide terminal detail; kit log under `.distsshkit/setup/` still written |
| `--progress` | Live status (TTY default) |
| `--verbose` | Full detail (non-TTY default) |
| `-y` / `--yes` | Accept confirmation prompts non-interactively |
| `--hosts CSV` | Comma-separated SSH hosts (`host:N` → host name only) |
| `--hosts-file PATH` | Append SSH hosts (`host:N` → host name only) |
| `-v` / `--version` | Print DistSSHKit version and exit |
| `-h` / `--help` | Full help |

`--clone` / `--rsync` never overwrite a nonempty remote path; use `--delete`
first to replace. `DISTSSHKIT_JOBS` (default 1) may rsync several hosts at once.

## Remote path

Default: `~/Parent/RepoName` from the local tree. Override with
`--remote-path` or `DISTRIBUTED_REMOTE_PROJECT_ROOT` (same ENV for `go` /
`drive`).

`~` is fine for setup shell ops (`rsync` / `clone` / `check`). Before
controller-side collect / path math, DistSSHKit expands `~` **on each SSH
host** to an absolute path. Prefer an absolute remote root when you can.

## After `--rsync`

No remote `.git/` — that is fine. `go` / `drive` do not pre-run sync or
require git parity by default. Kit logs: `{project}/.distsshkit/setup/`.
Ignore `.distsshkit/` in the job project ([User Guide](@ref Manual)).
