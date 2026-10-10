# [setup](@id Manual-setup)

Prepare SSH hosts before [`go`](@ref Manual-go) / [`drive`](@ref Manual-drive).

```bash
julia --project=. -m DistSSHKit setup [options] [child:NAME]
# Repeat child:NAME for more hosts. (:N ignored). parent is `up`, not setup.
```

From Julia, use [`setup!`](@ref) for the same modes as this CLI
(`:delete`, `:rsync`, `:clone`, `:instantiate`, `:check`, `:runtest`,
`:prune`, …), or the shorter [`sync!`](@ref) / [`instantiate!`](@ref) aliases
([API](@ref API), [First Steps · Prepare](@ref Tutorial-Prepare)).
The Julia channel is [`up`](@ref Manual-up), not a setup mode. The setup
parser still accepts `--juliaup` and `--juliaup-update`; they do the same
work as `up` / `up update`.
`setup!(session, :clone)` requires an explicit `repo=` URL (clone runs
on the remote).

Also: [Requirements](@ref), `setup --help`. Flag vocabulary:
[User Guide](@ref Manual).

## [rsync or git?](@id Manual-setup-rsync-or-git)

- **`--rsync`** — just sends your local files as-is; no git needed on the
  remote. Good for a first try or a one-off run. The tree is the directory
  that holds the Manifest Pkg reads, so a workspace member also sends that
  parent. `--project` on workers stays the member, and `go` runs in that
  directory. A lock outside that tree, a symlink to such a lock, or a lock
  outside the git work tree for `--clone` / `--sync`, fails before
  instantiate.
- **`--clone` then `--sync`** — manages the remote as a git repository. The
  clone lands on the git work tree root, placed so the Manifest directory
  is the same deploy root `--rsync` uses. Better if you're updating the
  code continuously, or you want [`drive --require-git`](@ref Manual-drive)
  to confirm the remote commit matches your local one for reproducibility.

## Flags

Pick **one mode** per invocation (except shared options).

- `--check`: local `ssh` / `rsync` / `git` on PATH; remotes: SSH, Julia,
  project, deps; git commit parity when remotes have `.git/`. A missing
  local git commit is a warning (instantiate still proceeds), not a fail
- `--clone`: `git clone` onto each remote at an empty/missing path
  (confirm unless `-y`)
- `--rsync`: rsync local tree onto missing/empty path (recommended first
  deploy; no remote `.git/`; confirm unless `-y`)
- `--sync`: local `git push`, then `git pull` on remotes (git workflows;
  confirm unless `-y`)
- `--pull`: `git pull` on laptop first, then remotes (no push; confirm
  unless `-y`)
- `--instantiate`: `Pkg.instantiate` on remotes after deploy
- `up` / `up update`: not a setup flag. See [Julia version](@ref Manual-up).
  `up child:NAME` and `up parent` run `add` / `update` /
  `default`. `up update` runs `juliaup update` and leaves the default
- `--runtest`: `Pkg.test()` of the **job** project on remotes (not
  DistSSHKit's tests)
- `--prune`: delete `.distsshkit/{go,drive,setup,runs}` leaves on localhost
  (job project) and remotes (confirm unless `-y`). Does not `--delete`
  the deploy tree. `--older-than DAYS` (mtime). `--id TOKEN` (go batch
  or `runs/<kind>/<leaf>` name contains TOKEN; skips drive/setup)
- `--cleanup`: kill stale Julia worker processes (local + remotes;
  untagged `julia --worker` / `--bind-to`. Drive leftover pkill is
  `job_id`-tagged only; `DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL=1` skips that)
- `--delete`: remove the remote tree (destructive; confirm unless `-y`).
  A git checkout removes the clone destination when that path sits above
  the deploy root. A `--remote-path` that cannot express that parent, and
  a tree with no git work tree, remove the rsync deploy root.
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
- `--hosts CSV`: comma-separated `child:NAME[:N]` (`:N` stripped).
  `parent` / `parent:N` belong to `up`, not `setup`
- `--hosts-file PATH`: append the same tokens (`:N` stripped)
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
path instantiate if deps are still missing. Setup logs:
`{project}/.distsshkit/setup/`.
`setup --rsync` skips `.distsshkit/` even if the job `.gitignore` is missing.
