# [serve](@id Queue-serve)

Run or register `serve` on the queue host.

```bash
julia -m DistSSHKit qhost serve [--interval S]
julia -m DistSSHKit stop
julia -m DistSSHKit qhost enable [--queue-env DIR]
julia -m DistSSHKit qhost disable
```

Also: [Prepare](@ref Queue-Tutorial-Prepare), [submit](@ref Queue-submit),
[setup](@ref Queue-setup). `qhost:` is refused (log in on the queue host).

`serve` is this terminal, now. Ctrl-C stops this process, not a job that is already running. Before each `execute!` it `Pkg.instantiate`s
the job project on this host, then `setup!` (`rsync` →
`instantiate` → `check`) on
`child:` hosts, unless
`DISTSSHQUEUE_NO_KIT_SETUP=1`. `setup!` does not instantiate
`parent`. Child `instantiate` / `check` failure fails the job.
A `qhost:` stage omits `.git/` (rsync); a missing local git commit
warns instead of failing `:check`
([DistSSHKit#370](https://github.com/yamanori99/DistSSHKit.jl/issues/370)). A
later job's `rsync` onto a nonempty worker path follows the no-overwrite
rule; `instantiate` still runs.

For normal jobs, `serve` does not choose `output_dir`. The job owns the
artifact leaf and run bundle. The queue records `run_dir` and a `run.toml`
snapshot on the row for cancel and fetch. See
[Artifacts and paths](@ref Queue-artifacts) and
[Job record](@ref Queue-job-record).

`enable` tells the OS to start `serve` after reboot / login
(LaunchAgent / systemd). `submit` starts `serve` if none is up.

## Flags

| Flag | Meaning |
| --- | --- |
| `--interval S` | `serve` poll interval (default `0.2`) |
| `--queue-env DIR` | `enable`: `julia --project=` in the OS unit |
| `--julia PATH` | `enable`: Julia binary in that unit |
| `--write-only` | `enable` / `disable`: write or remove the unit file without `launchctl` / `systemctl` |
| `-h` / `--help` | Queue usage |

`enable --project` is refused. Project stays cwd /
`DISTRIBUTED_PROJECT_ROOT`.

A dedicated env at `~/.distsshqueue/env`, if present, is the default
`--queue-env`. Prefer that so a checkout can be deleted.

## stop

Halts `serve`, keeps config / store / OS unit. Writes
(`jobs.toml.stopped`) so `submit` will not auto-start; only an explicit
`serve` resumes. Clients can `qhost:HOST stop`.

`disable` removes the OS unit. It does not delete the job table.
`Removed` when a unit file was deleted; `Present` (unchanged) when there
was nothing to drop. LaunchAgent / systemd still unload unless
`--write-only`.
