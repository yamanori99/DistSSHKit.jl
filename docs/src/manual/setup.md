# [setup](@id Manual-setup)

Prepare SSH hosts before [`go`](@ref Manual-go) / [`drive`](@ref Manual-drive).

```bash
julia --project=. -m DistSSHKit setup [options] HOST...
```

From Julia, use [`setup!`](@ref) for the same modes as this CLI
(`:delete`, `:rsync`, `:clone`, `:instantiate`, `:juliaup`, `:check`, `:runtest`,
`:prune`, …), or the shorter [`sync!`](@ref) / [`instantiate!`](@ref) aliases
([API](@ref API), [First Steps · Prepare](@ref Tutorial-Prepare)).
`setup!(session, :clone)` requires an explicit `repo=` URL (clone runs
on the remote).

Also: [Requirements](@ref), `setup --help`. Flag vocabulary:
[User Guide](@ref Manual).

## [rsync or git?](@id Manual-setup-rsync-or-git)

- **`--rsync`** — just sends your local files as-is; no git needed on the
  remote. Good for a first try or a one-off run.
- **`--clone` then `--sync`** — manages the remote as a git repository. Better
  if you're updating the code continuously, or you want
  [`drive --require-git`](@ref Manual-drive) to confirm the remote commit
  matches your local one for reproducibility.

## Flags

Pick **one mode** per invocation (except shared options).

- `--check`: local `ssh` / `rsync` / `git` on PATH; remotes: SSH, Julia,
  project, deps; git commit parity when remotes have `.git/`
- `--clone`: `git clone` onto each remote at an empty/missing path
  (confirm unless `-y`)
- `--rsync`: rsync local tree onto missing/empty path (recommended first
  deploy; no remote `.git/`; confirm unless `-y`)
- `--sync`: local `git push`, then `git pull` on remotes (git workflows;
  confirm unless `-y`)
- `--pull`: `git pull` on laptop first, then remotes (no push; confirm
  unless `-y`)
- `--instantiate`: `Pkg.instantiate` on remotes after deploy
- `--juliaup`: align Julia via juliaup to the kit parent major.minor
  (`add` / `update` / `default`; confirm unless `-y`; changes host
  default). Targets: SSH hosts and/or `parent` (this machine). Requires
  juliaup already on the target (`$HOME/.juliaup/bin/juliaup` or macOS
  Homebrew `/opt/homebrew/bin/juliaup` / `/usr/local/bin/juliaup`). Does
  not change the Julia process already running the kit. If remotes land
  on a newer patch than the kit parent, prints a Tip pointing at
  `setup --juliaup parent`
- `--runtest`: `Pkg.test()` of the **job** project on remotes (not
  DistSSHKit's tests)
- `--prune`: delete `.distsshkit/{go,drive,setup}` leaves on localhost
  (job project) and remotes (confirm unless `-y`). Does not `--delete`
  the deploy tree. `--older-than DAYS` (mtime). `--id TOKEN` (go batch
  name contains TOKEN; skips drive/setup)
- `--cleanup`: kill stale Julia worker processes (local + remotes);
  `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1` skips the `pkill`
- `--delete`: remove remote project dirs (destructive; confirm unless
  `-y`)
- `--repo URL`: clone URL (default: local `origin`)
- `--remote-path PATH`: remote repo root (alias `--remote-dir`; or
  `DISTRIBUTED_REMOTE_PROJECT_ROOT`)
- `--julia PATH`: Julia on remotes (default: auto /
  `JULIA_DISTRIBUTED_EXE`)
- `--ignore-julia-version`: warn instead of fail on major.minor mismatch
- `-q` / `--quiet`: hide terminal detail; kit log under
  `.distsshkit/setup/` still written
- `--progress`: live status (TTY default)
- `--verbose`: full detail (non-TTY default)
- `-y` / `--yes`: accept confirmation prompts non-interactively
- `--hosts CSV`: comma-separated SSH hosts (`host:N` → host name only)
- `--hosts-file PATH`: append SSH hosts (`host:N` → host name only)
- `-v` / `--version`: print DistSSHKit version and exit
- `-h` / `--help`: full help

`--clone` / `--rsync` never overwrite a nonempty remote path; use `--delete`
first to replace. `DISTSSHKIT_JOBS` (default 1) may rsync several hosts at once.
Non-quiet setup and [`setup!`](@ref) print a Time table with a row per host
(`rsync/host`, …). Replay with
`julia -m DistSSHKit progress .distsshkit/setup`.

## Remote path

Default: `~/Parent/RepoName` from the local tree. Override with
`--remote-path` or `DISTRIBUTED_REMOTE_PROJECT_ROOT` (same ENV for `go` /
`drive`).

`~` is fine for setup shell ops (`rsync` / `clone` / `check`). Before
kit-parent-side collect / path math, DistSSHKit expands `~` **on each SSH
host** to an absolute path. Prefer an absolute remote root when you can.

## After `--rsync`

No remote `.git/` — that is fine. `go` / `drive` do not pre-run sync or
require git parity by default. `go --rsync` / `drive --rsync` on an empty
path instantiate if deps are still missing. Kit logs:
`{project}/.distsshkit/setup/`.
`setup --rsync` skips `.distsshkit/` even if the job `.gitignore` is missing.
