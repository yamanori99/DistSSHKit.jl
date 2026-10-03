# [setup](@id Queue-setup)

Write config, or wipe Queue state on this host.

```bash
julia -m DistSSHQueue setup [--force]
julia -m DistSSHQueue setup --juliaup
julia -m DistSSHQueue setup --juliaup-update
julia -m DistSSHQueue teardown -y
```

Also: [Prepare](@ref Queue-Tutorial-Prepare), [Walkthrough](@ref Queue-Tutorial-Walkthrough), [serve](@ref Queue-serve),
[hosts](@ref Queue-hosts). `setup` refuses `qhost:`. `teardown` without
`-y` prints `Would remove` (exit 0) and does not delete. `-y` / `--yes`
or `DISTSSHKIT_YES` actually wipes. From a client: `qhost:HOST teardown
-y`.

`setup` is optional. Defaults work without `config.toml`. Re-run is a
no-op unless `--force`. It writes `config.toml` only, not
`~/.distsshqueue/env`.

## Flags

| Flag | Meaning |
| --- | --- |
| `--force` | `setup`: rewrite `config.toml` (not with juliaup) |
| `--juliaup` | Set config hosts to this major.minor |
| `--juliaup-update` | Patch config hosts; leave default |
| `--config PATH` | `setup` / `teardown`: config path (`DISTSSHQUEUE_CONFIG`) |
| `-y` / `--yes` | `teardown`: confirm (`DISTSSHKIT_YES`; same values as DistSSHKit) |
| `--write-only` | `teardown`: do not stop `serve` or unload the OS unit |
| `--home DIR` | `teardown`: home for `~/.distsshqueue` |
| `--bindir DIR` | `teardown`: leftover `dskq` shim path |
| `-h` / `--help` | Queue usage |

`DISTSSHQUEUE_YES` is gone. `[env]` in the target `config.toml`
still applies.

## teardown

Stops `serve`, removes the OS unit and `~/.distsshqueue`. Does
not `Pkg.rm`, and never deletes a git clone or Kit `.distsshkit/`
results. Trees: [Where files live](@ref Requirements). Still removes leftover
`~/.distsshkitqueue`, old `org.distsshkitqueue.serve` units, and
`~/.local/bin/dskq` if present.

## config.toml

`~/.distsshqueue/config.toml`. Override:
`DISTSSHQUEUE_CONFIG`. Resolution: CLI / ENV > config.toml >
built-in defaults. `[env]` keys use `get!` so a real ENV value wins.

```toml
store = "~/.distsshqueue/jobs.toml"
# hosts = ["parent", "child:host1:4"]

[env]
# DISTRIBUTED_SSH_OPTS = "-F /path/to/ssh_config"
# DISTSSHKIT_YES = "1"
# Do not set DISTRIBUTED_REMOTE_PROJECT_ROOT here on a shared queue host.
```

| Key | Meaning |
| --- | --- |
| `store` | Job table path (`DISTSSHQUEUE_STORE`) |
| `hosts` | Kit tokens; missing = CLI needs `add-host` before a named token; `[]` = allow none |
| `[env]` | Default ENV for this host (not `DISTSSHQUEUE_HOST`). Skip `DISTRIBUTED_REMOTE_PROJECT_ROOT` unless this box is one job |

CLI `submit` re-reads `hosts` each time
([submit](@ref Queue-submit)). Library [`submit!`](@ref) uses
`Queue(; allowed=…)` unless `follow_config=true`.
