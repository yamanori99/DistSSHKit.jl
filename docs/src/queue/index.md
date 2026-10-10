# [How it runs](@id Queue-manual)

Leave jobs on a machine that stays on. They run one at a time.
`julia -m DistSSHKit` accepts `submit`, `serve`, `status`, and the rest
of this section. On that machine, `setup`, and `size` / `plan` / `pool`,
stay `julia -m DistSSHKit`.

For a hands-on path, use First Steps
([Requirements](@ref) → [Prepare the machine](@ref Queue-Tutorial-Prepare) →
[Walkthrough](@ref Queue-Tutorial-Walkthrough)).

Root `--help` defines Client vs the machine that stays on (`qhost:HOST`), then Usage,
then `--help client` / `--help qhost`. `julia -m DistSSHKit -v` prints
`DistSSHKit X`. A command on that machine can still print
`DistSSHQueue X (DistSSHRun Y)`. `--help client` is Jobs then Hosts;
`--help qhost` is Setup, Serve, then Danger (`teardown`; needs `-y`;
job trees stay). `<command> -h` is that verb's Usage and Flags.
Command argv is on
`--help client`. Flags and FAQ:
`julia --project=. -m DistSSHKit <command> -h` and the pages below.
Each command page starts with **Usage**, then **Flags**.
`go` / `ride` / `drive` / `size` / `plan` / `pool` flags stay in the
[User Guide](@ref Manual).

| | |
| --- | --- |
| [Artifacts and paths](@ref Queue-artifacts) | Where the script, the job, and the waiting jobs keep files |
| [submit](@ref Queue-submit) | Leave `go` / `ride` / `drive` there |
| [status](@ref Queue-status) | `status` / `watch` / `cancel` |
| [fetch](@ref Queue-fetch) | Copy a finished leaf onto this job tree |
| [hosts](@ref Queue-hosts) | `add-host` / `remove-host` / `list-host` / `size` / `plan` / `pool` |
| [serve](@ref Queue-serve) | `serve` / `stop` / `enable` / `disable` |
| [setup](@ref Queue-setup) | `setup` / `teardown` / `config.toml` |

## Client vs queue host

`qhost:HOST` is a **client** token (like `child:NAME`). Not already
on the queue host: put it on the command line (leading or right after
the verb).
`DISTSSHQUEUE_HOST` alone does not hop. On the queue host, omit
`qhost:`. After `teardown`, `status` without `qhost:` asks for `setup`
first (the config is gone), or `qhost:HOST` if this was a client hop.
Local trial: `DISTSSHQUEUE_LOCAL=1`.

Refuse `qhost:`: `setup`, `serve`, `enable`, `disable`, `add-host`,
`remove-host`. Forward: `submit`, `status`, `list-host`, `size`, `plan`,
`pool`, `watch`, `cancel`, `stop`, `teardown`. Client (not forwarded as a
whole): `fetch` (inverse of stage).

`--hosts` / `--julia` belong to `go` / `ride` / `drive`. Queue-host Julia is
`--remote-julia` / `JULIA_DISTRIBUTED_EXE`. `--queue-env DIR` is
`julia --project=` on the queue host (default `~/.distsshqueue/env` if
you created that dir), not the client's `--project=.`. `--queue-env @`
is the remote default Julia env. Hop is argv `qhost:HOST` (not
`DISTSSHKIT_HOSTS`). `DISTSSHQUEUE_HOST` alone does not hop. Not forwarded.
Not `DISTSSHQUEUE_QHOST` (that is `status` / `watch` display).

`serve` is “run the process”. `enable` is “register that process with
the OS” (LaunchAgent / systemd). The queue host is **macOS or Linux**.
`enable` does not make a client or WSL2 the always-on box. `disable`
is the opposite of `enable`, not of `serve`.

## [Job record](@id Queue-job-record)

Each row contains:

- Identity: `id`, `kind`, `script`, and `hosts`
- State: `state`, `queued_at`, `started_at`, `finished_at`, and `error`
- Output references: `result_path`, `run_dir`, a `run_toml` snapshot,
  and setup log paths when applicable

The waiting list does not keep a second copy of the job's result tree or
normally pin `output_dir`. See
[Artifacts and paths](@ref Queue-artifacts) for the output contract.

Job kwargs (`args`,
`project`, `output_dir`, …) travel as an opaque bag through DistSSHKit's
`execute!` allow-list. `serve` also passes `job_id` (the row UUID)
so progress lines can carry `job=`. `serve` instantiates the job
project on the queue host, then `setup!` on `child:` hosts, unless
`DISTSSHQUEUE_NO_KIT_SETUP=1`.

### Store files

The queue-host table is `~/.distsshqueue/jobs.toml`.

- Writers lock `jobs.toml.lock` before rewriting the table.
- The rewrite truncates in place and is not atomic.
- `status` and `watch` read without the lock and may encounter a
  mid-write table.
- `jobs.toml.pid` identifies a live `serve`; a dead pid is ignored.
- `jobs.toml.stopped` blocks autoserve after `stop` until an explicit
  `serve`.

If writers hang and no Queue process holds the lock, remove a stale
`jobs.toml.lock`. See [Where files live](@ref Requirements) for all
paths.

### Recovery after `serve` exits

- `:queued` rows reload on the next `serve`.
- A `:running` row with a live `kit.pid` remains `:running` and
  blocks the next FIFO job.
- Without a live `kit.pid`, `kit.result` determines `:done` or
  `:failed`; without that result, the row becomes `:failed`.

For drive, listed `parent` / `child` hosts must join, stay, and collect
unless the job passed `--best-effort`. See
[drive](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/drive/).
`go` / `ride` / `drive` artifacts stay under the job's `.distsshkit/` tree. `fetch`
creates the client copy described in
[Artifacts and paths](@ref Queue-artifacts).

## Shared peel

| Topic | Rule |
| --- | --- |
| `-q` / `--quiet` | `status` / `watch`: table only. `DISTSSHKIT_QUIET`. |
| `--progress` / `--verbose` | Accepted (exclusive with `-q`); there is no live run to paint, so they keep chrome. |
| `-v` / `--version` | Top-level: this package, then DistSSHKit. `submit go -v` is the `go` command only. |
| `-y` / `--yes` | `teardown` (or `DISTSSHKIT_YES`). Same values as DistSSHKit. |
| Ctrl-C | `serve` / `watch`: that process only, never a job that is already running. |

## Out of scope

A scheduler inside DistSSHKit, weakdeps from Queue to DistSSHKit, a glue
package, lab-wide slot ceilings or occupancy packing, preemption /
fair-share / priorities / reservations / backfill, HTTP or a listen
socket, a client that sleeps as `serve`, auto-retry of crashed
`:running` jobs, a second copy of the job's result trees, and native
Windows. Day-to-day consequences of the single FIFO:
[How it runs](@ref Queue-manual).
