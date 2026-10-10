# [submit](@id Queue-submit)

Enqueue a DistSSHKit `go`, `ride`, or `drive`. Starts `serve` if none is
running. That `serve` instantiates the job project on the queue host
and runs `setup!` on `child:` hosts before `execute!` (not a
hand-run DistSSHKit `setup` on the stage tree). `:check` always
runs on `child:` hosts (warns if a `qhost:`
stage has no `.git/`).

Type the line on a **client**, in the **job directory** (Queue must be
loadable; `--project=.` is that tree, and `SCRIPT.jl` lives there). Not
already on the queue host: include `qhost:HOST`. Already logged in on
that always-on machine? Same directory, omit `qhost:`. Do not type this
on a worker. `serve` on the queue host runs the DistSSHKit argv later.

```bash
cd ~/my-job    # Project.toml, SCRIPT.jl; Queue loadable

# another machine (not the queue host)
julia --project=. -m DistSSHKit qhost:HOST submit drive parent:4 SCRIPT.jl

# already on the queue host
julia --project=. -m DistSSHKit submit drive parent:4 SCRIPT.jl
```

One argv, four nested pieces. `qhost:HOST` is the SSH name of that
queue machine. `submit` is Queue. The next word is the DistSSHKit kind
(`go` / `ride` / `drive`); after that, argv matches DistSSHKit.

```bash
julia --project=. -m DistSSHKit  [qhost:HOST]  submit  drive  parent:4  SCRIPT.jl
#──────────── Julia ────────────┘  └─ qhost ──┘  Queue   └─── DistSSHKit argv ────┘
```

```bash
julia --project=. -m DistSSHKit [qhost:HOST] submit drive parent:4 SCRIPT.jl
```

A long line in the terminal is still one command. Break after `submit` with `\`:

```bash
julia --project=. -m DistSSHKit [qhost:HOST] submit \
    drive parent:4 child:NAME:N SCRIPT.jl
```

The same argv, started on this machine now:

```bash
julia --project=. -m DistSSHKit drive parent:4 SCRIPT.jl
```

That starts compute on **this** machine, now. `submit` only enqueues the
same argv; `serve` runs it later on the queue host (after `qhost:`, on
the staged tree). Start the same argv on this machine to debug placement, then enqueue.

`pool:N` sits next to `submit`. It is not a host token: it expands config `hosts` to the same `:N`
(clamped by add-host max). Place it next to `submit` (before or after
the kind), not among `parent` / `child` tokens. Library [`submit!`](@ref)
does not expand `pool:N`. Inspect `pool` (no enqueue) is
[User Guide · hosts](@ref Queue-hosts).

```bash
julia --project=. -m DistSSHKit  [qhost:HOST]  submit  pool:8  drive  SCRIPT.jl
#──────────── Julia ────────────┘  └─ qhost ──┘  └─ submit ──┘  └─ go / ride / drive ─┘
```

A `.jl` with no verb for the waiting list is not implicit `go` (same as `go` / `ride` / `drive` on this machine). Top-level
`go` / `ride` / `drive` are DistSSHKit; enqueue with `submit`. `ride` is
experimental.

Also: [First job](@ref Queue-Tutorial-Client), [Walkthrough](@ref Queue-Tutorial-Walkthrough),
[hosts](@ref Queue-hosts),
`julia -m DistSSHKit --help`. Flags:
[go](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/go/),
[ride](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/ride/),
[drive](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/drive/).

CLI `submit` uses `Queue(; follow_config=true)` so each enqueue
re-reads config `hosts`. Library [`submit!`](@ref) uses
`Queue(; allowed=…)` unless `follow_config=true`.

With `qhost:`, the client **rsync**s the job project (`cwd` /
`DISTRIBUTED_PROJECT_ROOT`) to `~/.distsshqueue/stage/<uuid>` on the
queue host (rsync excludes: `.gitignore`, `.git/`, `.distsshkit/`,
`.distsshqueue/`), then enqueue resolves
`SCRIPT.jl` there. The client keeps `.distsshqueue/tickets/<uuid>`
(every `qhost:` submit from this tree; not an artifact).
[Artifacts and paths](@ref Queue-artifacts) explains stage, ticket,
the job's output, and the [`fetch`](@ref Queue-fetch) destination. Omit `qhost:`:
the script is checked on this machine. Job id prints as a bare stdout line. CLI `submit` also prints
`queue: local (HOSTNAME)` (or `qhost: local (HOSTNAME)` on the hopped
process when you passed `qhost:`) then `Queued  N (no running)` on stderr
(`(R running)` when a job is already running);
`DISTSSHKIT_QUIET` hides that. A `qhost:` rsync prints `rsync → HOST:…` when it starts (fetch: `rsync ←`). `DISTSSHKIT_PROGRESS` / `--progress` adds rsync `--info=progress2`. Missing config `hosts`: a `parent` / `child:` token is an error (`add-host first`). `hosts = []` allows none.

Two different projects
that a job from this machine would deploy to the same worker path are refused (no
rename, no `setup --delete`). The same project may be submitted again.

## Flags

`go` / `ride` / `drive` argv is forwarded as-is. The extra on
this line is `pool:N` (above). A drive row is `:done` when `ok` is true (listed hosts
must join unless `--best-effort`).

| Flag | Meaning |
| --- | --- |
| `go` / `ride` / `drive` | DistSSHKit kind (`execute!`) |
| Host tokens | `parent[:N]` / `child:NAME[:N]` (not a cap on how many jobs wait) |
| `pool:N` | Same `:N` on every config host |
| `--hosts` / `--julia` | Belong to `go` / `ride` / `drive`. Julia on the machine that stays on is `--remote-julia` / `JULIA_DISTRIBUTED_EXE` |
| `-v` / `--version` | On `submit go` / `ride` / `drive`: that command only |
| `-h` / `--help` | Help for that kind |

Opt out of auto `serve`: `DISTSSHQUEUE_NO_AUTOSERVE=1`. A prior
[`stop`](@ref Queue-serve) also holds `serve` off until an
explicit `serve`.

A job that is already `:running` is not stopped when `hosts` changes. `:queued`
rows still start if a name is later removed.
