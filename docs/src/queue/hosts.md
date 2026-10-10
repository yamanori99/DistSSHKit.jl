# [hosts](@id Queue-hosts)

Lab inventory and DistSSHKit `size` / `plan` / `pool` on the queue host. These verbs do
not enqueue. Not `--hosts` (that still names workers on `go` /
`ride` / `drive`).

```bash
julia -m DistSSHKit qhost add-host parent child:host1
julia -m DistSSHKit list-host
julia -m DistSSHKit qhost size
julia -m DistSSHKit qhost remove-host child:host1
```

From a **client**, `list-host`, `size`, `plan`, and `pool` are forwarded like `status`.
`add-host` / `remove-host` run on the queue host only (like `setup`).
A major.minor Julia mismatch vs this process is a warning only
(`DISTSSHKIT_QUIET` silences it). Fix: `qhost up`.

Also: [Prepare](@ref Queue-Tutorial-Prepare), [submit](@ref Queue-submit),
[kit size](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/size/),
[kit plan](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/plan/),
[kit pool](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/pool/).

## add-host / remove-host

Write host tokens into config `hosts`
(`parent[:N]` / `child:NAME[:N]`). `parent` is slots on this queue
host, not an SSH Host named parent. `child:NAME` is SSH `Host NAME`.
`add-host child:` prints a warning: anyone who can `submit` as this
queue-host user (including `qhost:`) can use those names via DistSSHKit
(`DISTSSHKIT_QUIET` hides it). A second line: those hosts need outbound
internet for `instantiate` unless the Julia depot already has the
registry and packages. SSH/rsync success is not enough if instantiate
still has to fetch. A nonempty `~/.julia` is not that test. See
[Requirements](@ref) (one trust
domain). Optional `:N` is a per-name max.

| | |
| --- | --- |
| Missing `hosts` | Named tokens error unless leftover `allowed` (`add-host first`) |
| First `add-host` | Creates `hosts` |
| `hosts = []` | Last `remove-host`; submit accepts none |
| Leftover `allowed` | Inventory until `add-host` rewrites it to `hosts` |

No `serve` restart. Next [`submit`](@ref Queue-submit) re-reads the
file. A job that is already `:running` is not stopped.

## list-host

Read-only. One row per host: NAME / TOKEN / MAX / JULIA / SSH.
NAME for `parent` is this queue host's
hostname; TOKEN stays `parent` (copy-paste for `submit`, including
`parent:N`). Children: NAME is the SSH Host, TOKEN is `child:NAME`.
JULIA is that host's `juliaup default` patch (`1.12.7` from the `*`
Version column); `-` if juliaup is missing, SSH or `status` fails, or
there is no Version on the `*` row.
SSH is `this machine` locally, `queue host` via `qhost:`, else
`user@hostname` from `ssh -G` (`:port` when not 22). No private keys
or IdentityFile. `ssh -G` runs on the queue host. NAME is still the
queue host's hostname, not the client's.

```bash
julia -m DistSSHKit qhost:HOST list-host
```

## size

DistSSHKit `size` on the queue host (cwd / project). Omit tokens to size
config `hosts`. Does not enqueue. Prints a `submit drive` template.

```bash
julia -m DistSSHKit qhost:HOST size
julia -m DistSSHKit qhost:HOST size --gb-per-worker 1.5 parent child:host1
```

Flags (`--probe`, `--gb-per-worker`, …):
[size](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/size/).
`size --help` adds a note under that command's help.

## plan

DistSSHKit `plan` on the queue host (cwd / project). Inspects a script
and suggests `go` / `ride` / `drive`. Does not enqueue. Prints a
`submit` template for that kind.

```bash
julia -m DistSSHKit qhost:HOST plan SCRIPT.jl
```

Flags:
[plan](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/plan/).
`plan --help` adds a note under that command's help.

## pool

`pool` wraps the same `pool` on the queue host (cwd / project).
Cores / RAM / slot hint (no RSS). Omit tokens: config
`hosts` are passed. Does not enqueue. Prints sizing notes and a
`Suggested submit (template):` footer (always `submit drive`; use `size`
to measure RSS). Same nesting as submit: the verb, then host
tokens. Enqueue with the same `:N` on every config host is
`submit pool:N` ([submit](@ref Queue-submit)).

```text
julia -m DistSSHKit  [qhost:HOST]  pool  parent  child:host1
└── Julia ──┘  └── queue host ──┘  └─ pool ┘  └──── host tokens ────────┘
```

```bash
julia -m DistSSHKit qhost:HOST pool
julia -m DistSSHKit qhost:HOST pool parent child:host1
```

Flags:
[pool](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/pool/).
`pool --help` adds a note under that command's help.
