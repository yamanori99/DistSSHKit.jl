# [go](@id Manual-go)

Run a **standalone** script as-is (no Kit APIs in the job file). Each
`parent:N` / `child:NAME:N` slot is one full script run, started
**concurrently** — not Distributed workers.

```bash
julia --project=. -m DistSSHKit go [options] \
  [parent:N] [child:NAME[:N]...] SCRIPT.jl [script_args...]
```

Also: [First Steps · Demo](@ref Tutorial-Demo), [drive](@ref Manual-drive),
`go --help`. Flag vocabulary and a short **go vs drive** table:
[User Guide](@ref Manual).

**vs drive:** each `child:NAME:N` is N full script runs (not Distributed
workers). There is no `--require-git`; for commit parity use
[`drive --require-git`](@ref Manual-drive).
Prepare remotes with [`setup --rsync`](@ref Manual-setup) **or** `--clone`, then
`--instantiate`. One-shot onto an empty/missing path: `go --rsync` (instantiates
if needed). Later git updates (`setup --sync` / `go --sync`) need a
`--clone` / git-managed remote, not an rsync tree.

## Flags

- `--sync`: git push/pull before remote slots (**opt-in**; default is none;
  confirm unless `-y`)
- `--rsync`: rsync working tree first (empty/missing remote, or after
  `setup --delete`); then instantiate if deps are missing
- `--skip-sync`: compat: no pre-run sync (already the default)
- `--skip-git-guard`: alias of `--skip-sync` (shared name with drive)
- `--julia PATH`: Julia on remotes (default: auto / `JULIA_DISTRIBUTED_EXE`)
- `--output-dir PATH`: **batch root**; slots write under `PATH/{slot}/`
  (not `drive --output-dir`)
- `--hosts CSV`: comma-separated slot specs (same form as CLI tokens /
  `DISTSSHKIT_HOSTS`)
- `-q` / `--quiet`: hide terminal detail; `go_*.log` and per-slot logs
  still written
- `--progress`: live status (TTY default)
- `--verbose`: full detail (non-TTY default)
- `-y` / `--yes`: non-interactive confirmations
- `--hosts-file PATH`: append slot specs (`child:NAME:N` preserved)
- `--repeat N`: N independent runs in total. Spread round-robin across
  listed hosts (none → all on parent). Omit `:N` on a host to leave it
  uncapped; `parent:N` / `child:NAME:N` are per-host caps.
- `-v` / `--version`: print DistSSHKit version and exit
- `-h` / `--help`: full help

`--sync` / `--rsync` / `--skip-sync` (and `--skip-git-guard`) are mutually
exclusive.
Default pre-run sync is **none** (same as [`drive`](@ref Manual-drive));
prepare remotes with [`setup`](@ref Manual-setup), or pass `--sync` / `--rsync`.
`--rsync` instantiates when the copied tree still lacks deps. `go` checks
`Project.toml` **after** that copy (empty remotes are allowed until then).

## Output

Default batch root (next to the script):

```text
{script}/.distsshkit/go/{stem}_{UTC}/{slot}/
```

If the script is outside the project, `{project}/.distsshkit/go/{stem}_{UTC}/`.
`--output-dir PATH` replaces the **batch root**. Kit sets
`DISTRIBUTED_OUTPUT_DIR` to each slot directory.
Add `.distsshkit/` to the job project's `.gitignore` so these paths stay
untracked and `setup --rsync` does not push them (rsync also excludes that
name). See [User Guide](@ref Manual).

From the API, `go!(...; output_dir=PATH)` sets the same batch root (matching
[`drive!`](@ref Manual-drive)). `collect_spec::String` still works as a
backward-compatible alias, but passing both `output_dir` and
`collect_spec::String` is an error. `collect_spec=false` skips collect and
is orthogonal to `output_dir`.

Collect after remote slots: **slot-overwrite** (rsync whole slot dir).
A failed slot pull is a failed slot, not an empty directory.
Any explicit slot that does not run (remote path missing, run ✗, collect ✗)
fails the batch (`ok=false`). There is no partial success.

External watchers: `begin` / `item` always go to `kit.progress` (even `-q`).
The kit log still gets those lines only with `--progress` or
`DISTSSHKIT_PROGRESS=1`. `progress: done` is always written.

## Wall time

Same as [drive](@ref Manual-drive): run go as usual (`-q` hides the table).
The Time table prints at the end, after slot stdout, with a `progress DIR`
line to replay:

```bash
julia --project=. -m DistSSHKit go -y parent:2 \
  distsshkit_demos/without_kit/pi_echo.jl --n 5000
julia --project=. -m DistSSHKit progress DIR
```

`DIR` is the batch root (`--output-dir`, or `{script}/.distsshkit/go/…`).
`--progress` is the TTY default; you do not need a scratch `--output-dir` just
to time a run.

Labels: `ready` (remote project / Julia, when remotes are listed), `sync`
(optional), `run` (all slot scripts), then `collect` (remote pulls). Nested
rows are `NAME/run` and `NAME/collect`. Scripts overlap with each other;
pulls wait until every script has finished (same order as drive: `collect`
then the rsync). Percentages are of the whole run and may sum past 100%.

## Concurrent runs

Two `go` runs (or `go!` calls) against the same batch root fail fast: a
`.kit.lock` file (this run's pid) is written under the batch root, and a
second run against the same directory raises immediately instead of
interleaving slot output. A lock left behind by a crashed/killed run is
detected as stale (dead pid) and reclaimed automatically. Since the default
batch root already includes a UTC timestamp, this mainly matters when you
pass an explicit `--output-dir` / `output_dir=`.

## `job_id`

`execute!(:go, …; job_id=)` and `ENV["DISTSSHKIT_JOB_ID"]` tag each slot so
[`terminate!`](@ref) / [`terminate_run!`](@ref) can
`pkill -f distsshkit-job:<id>`
without matching other Julias. The tag is a no-op `-L` file named
`distsshkit-job:<id>` in the slot directory; the user script remains
`PROGRAM_FILE` with the usual `ARGS`. Drive workers use a comment-only
`--eval=#distsshkit-job:<id>` instead (Distributed starts the worker; the
driver `include`s later). Unset `job_id`: no tag. Details: [API](@ref API).

## Hosts

CLI tokens, `--hosts`, `--hosts-file`, and/or `DISTSSHKIT_HOSTS`.
`parent:0` skips parent
slots when remotes are listed. Omitting hosts is one parent slot (`parent/`).
