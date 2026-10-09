# [submit](@id Queue-submit)

Enqueue a DistSSHKit `go`, `ride`, or `drive`. Starts `serve` if none is
running. That `serve` instantiates the job project on the queue host
and runs Kit `setup!` on `child:` hosts before `execute!` (not a
hand-run DistSSHKit `setup` on the stage tree). Kit `:check` always
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

The DistSSHKit argv runs as-is without Queue:

```bash
julia --project=. -m DistSSHKit drive parent:4 SCRIPT.jl
```

That starts compute on **this** machine, now. `submit` only enqueues the
same argv; `serve` runs it later on the queue host (after `qhost:`, on
the staged tree). Use Kit alone to debug placement, then enqueue.

`pool:N` is Queue, not Kit: it expands config `hosts` to the same `:N`
(clamped by add-host max). Place it next to `submit` (before or after
the kind), not among `parent` / `child` tokens. Library [`submit!`](@ref)
does not expand `pool:N`. Inspect `pool` (no enqueue) is
[User Guide · hosts](@ref Queue-hosts).

```bash
julia --project=. -m DistSSHKit  [qhost:HOST]  submit  pool:8  drive  SCRIPT.jl
#──────────── Julia ────────────┘  └─ qhost ──┘  └── Queue ───┘  └─ DistSSHKit -┘
```

A `.jl` with no Queue verb is not implicit `go` (same as Kit). Top-level
`go` / `ride` / `drive` are DistSSHKit; enqueue with `submit`. `ride` is
experimental.

Also: [First job](@ref Queue-Tutorial-Client), [Walkthrough](@ref Queue-Tutorial-Walkthrough),
[hosts](@ref Queue-hosts),
`julia -m DistSSHKit --help`. Kit flags:
[go](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/go/),
[ride](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/ride/),
[drive](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/drive/).

CLI `submit` uses `Queue(; follow_config=true)` so each enqueue
re-reads config `hosts`. Library [`submit!`](@ref) uses
`Queue(; allowed=…)` unless `follow_config=true`.

With `qhost:`, the client **rsync**s the job project (`cwd` /
`DISTRIBUTED_PROJECT_ROOT`) to `~/.distsshqueue/stage/<uuid>` on the
queue host (Kit rsync excludes: `.gitignore`, `.git/`, `.distsshkit/`,
`.distsshqueue/`), then enqueue resolves
`SCRIPT.jl` there. The client keeps `.distsshqueue/tickets/<uuid>`
(every `qhost:` submit from this tree; not an artifact).
[Artifacts and paths](@ref Queue-artifacts) explains stage, ticket,
Kit output, and the [`fetch`](@ref Queue-fetch) destination. Omit `qhost:`:
the script is checked on this machine. Job id prints as a bare stdout line. CLI `submit` also prints
`queue: local (HOSTNAME)` (or `qhost: local (HOSTNAME)` on the hopped
process when you passed `qhost:`) then `Queued  N (no running)` on stderr
(`(R running)` when a job is already running);
`DISTSSHKIT_QUIET` hides that. A `qhost:` rsync prints `rsync → HOST:…` when it starts (fetch: `rsync ←`). `DISTSSHKIT_PROGRESS` / `--progress` adds rsync `--info=progress2`. Missing config `hosts`: a `parent` / `child:` token is an error (`add-host first`). `hosts = []` allows none.

Two different projects
that Kit would deploy to the same worker path are refused (no
rename, no `setup --delete`). The same project may be submitted again.

## Flags

Kit `go` / `ride` / `drive` argv is forwarded as-is. Queue's extra on
this line is `pool:N` (above). A drive row is `:done` when Kit `ok` is true (listed hosts
must join unless `--best-effort`).

| Flag | Meaning |
| --- | --- |
| `go` / `ride` / `drive` | DistSSHKit kind (`execute!`) |
| Kit tokens | `parent[:N]` / `child:NAME[:N]` (not a Queue ceiling) |
| `pool:N` | Queue: same `:N` on every config host |
| `--hosts` / `--julia` | Kit's. Queue-host Julia is `--remote-julia` / `JULIA_DISTRIBUTED_EXE` |
| `-v` / `--version` | On `submit go` / `ride` / `drive`: Kit only |
| `-h` / `--help` | Kit help for that kind |

Opt out of auto `serve`: `DISTSSHQUEUE_NO_AUTOSERVE=1`. A prior
[`stop`](@ref Queue-serve) also holds `serve` off until an
explicit `serve`.

A `:running` Kit job is not stopped when `hosts` changes. `:queued`
rows still start if a name is later removed.
