# [First job](@id Queue-Tutorial-Client)

Submit from a **client** after the queue host is up
([Prepare](@ref Queue-Tutorial-Prepare)). Commands in order:
[Walkthrough](@ref Queue-Tutorial-Walkthrough). Also see
[User Guide · submit](@ref Queue-submit), [status](@ref Queue-status),
[fetch](@ref Queue-fetch), [Where files live](@ref Requirements), and
[Artifacts and paths](@ref Queue-artifacts).

## Point at the queue host

Run from a directory where Queue is loadable (`julia --project=.`).
That `--project=.` stays on the **client**. `qhost:` defaults to
`--project=~/.distsshqueue/env` on the queue host (`--queue-env DIR` /
`--queue-env @`). Create that dir if clients use `qhost:` (see Prepare).
`qhost:` **rsync**s the client job tree (`cwd` /
`DISTRIBUTED_PROJECT_ROOT`) to `~/.distsshqueue/stage/<uuid>` on the
queue host. After submit, this job tree has
`.distsshqueue/tickets/<uuid>` (not the Kit leaf; every submit stays).
`SCRIPT.jl` must exist on
the **client** in that tree.
Omit `qhost:`: no rsync; the script is on this machine. Kit still
copies queue host → workers.

```bash
julia --project=. -m DistSSHKit qhost:HOST list-host
julia --project=. -m DistSSHKit qhost:HOST size
julia --project=. -m DistSSHKit qhost:HOST plan SCRIPT.jl
julia --project=. -m DistSSHKit qhost:HOST pool
```

One queue host: still pass `qhost:HOST` (or `status qhost:HOST`).
`DISTSSHQUEUE_HOST` is not enough. Local trial without `qhost:`:
`DISTSSHQUEUE_LOCAL=1`. Several clusters: pass `qhost:` each time.

`list-host` is not Kit `--hosts`. One row: NAME / TOKEN / MAX / JULIA / SSH
(`user@hostname`, `:port` when not 22). `ssh -G` runs on the queue host.
`size` / `plan` / `pool` are DistSSHKit inspect verbs there (do not enqueue).

## Submit

One line, nested the same way as [User Guide · submit](@ref Queue-submit):

```text
julia -m DistSSHKit  [qhost:HOST]  submit  drive  parent:4  SCRIPT.jl
└── Julia ──┘  └── queue host ──┘  └Queue┘  └──────── DistSSHKit argv ────────┘
```

The tail is DistSSHKit. Same compute, now, on this machine:

```bash
julia --project=. -m DistSSHKit drive parent:4 SCRIPT.jl
```

Longer argv, still one command (`\` at the end of the line):

```bash
julia --project=. -m DistSSHKit qhost:HOST submit \
    drive parent:4 child:host1:4 SCRIPT.jl
```

`submit` only enqueues that argv for `serve` on the queue host.

Kit argv is DistSSHKit's (`go child:NAME:N SCRIPT.jl`, or `parent:N`
when workers are on the queue host). Flags:
[kit go](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/go/),
[kit ride](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/ride/),
[kit drive](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/drive/).

```bash
julia --project=. -m DistSSHKit qhost:HOST submit go child:host1:4 SCRIPT.jl
julia --project=. -m DistSSHKit qhost:HOST status
julia --project=. -m DistSSHKit qhost:HOST watch
julia --project=. -m DistSSHKit qhost:HOST cancel <id>
julia --project=. -m DistSSHKit qhost:HOST fetch <id>  # 8-char prefix or full UUID
julia --project=. -m DistSSHKit qhost:HOST fetch .distsshqueue/tickets/<uuid>
```

`submit` starts `serve` if none is running. `serve` instantiates the
job project on the queue host and runs Kit `setup!` on `child:` hosts
before `execute!`. Kit `:check` always runs on `child:` hosts
(warns if a `qhost:` stage has no `.git/`). `status` / `watch` print
`qhost` (or `local (hostname)` when you omitted it). `watch` is
`status --interval` until Ctrl-C; it does not stop `serve`. Job ids print as a bare
stdout line. `submit` also prints `Queued  N (no running)` on stderr unless
`DISTSSHKIT_QUIET` is set. A `qhost:` rsync prints `rsync → HOST:…` when
it starts (fetch: `rsync ←`). After `qhost:` submit,
`.distsshqueue/tickets/<uuid>` marks the job on this client. `fetch`
copies the finished result to `.distsshqueue/<kind>/<stem>_<id8>/`.
Run it from the same directory as `submit`. Drive CSV
(Kit `square_file.jl`) is in that
`.distsshqueue/drive/<stem>_<id8>/` leaf, not `output/`.

A `.jl` with no Queue verb is not implicit `go` (same as Kit). Top-level
`go` / `ride` / `drive` are DistSSHKit; enqueue with `submit`. `ride` is
experimental.

There is no `--via`. Do not pass `qhost:` to `setup` / `serve` /
`enable` / `disable` / `add-host` / `remove-host`.

Next: [Walkthrough](@ref Queue-Tutorial-Walkthrough), or [User Guide](@ref Queue-manual).
