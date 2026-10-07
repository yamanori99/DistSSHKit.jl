# [Artifacts and paths](@id Queue-artifacts)

DistSSHQueue schedules a run; it does not own the run's output format.
The three layers have separate responsibilities:

| Layer | Owns |
| --- | --- |
| Script | The files that are the result of the computation |
| DistSSHKit | The queue-host run bundle, artifact leaf, logs, and collected directories under `.distsshkit/` |
| DistSSHQueue | The job row and the client-side copy made by `fetch` under `.distsshqueue/` |

`serve` normally does not set `output_dir` for `go`, `ride`, or
`drive`. Kit and the script choose the artifact leaf. A script that
does not load DistSSHKit still works: the detached Kit process supplies
the run context around it.

## Queue host

A run has an artifact leaf and a separate sidecar:

```text
<job project>/
  SCRIPT.jl
  .distsshkit/
    runs/<kind>/<run>/       Kit run bundle
      run.toml               output_dir, logs, collect_dirs, ...
      kit.pid
      kit.result
    <kind>/SCRIPT_<UTC>_<id>/  primary artifact (Kit/script picks the leaf)
      ...                    files written by the script / Kit
    setup/*.log              Kit setup logs
```

Kit owns this tree. Queue records enough metadata in the job row to
schedule, cancel, and fetch without making another queue-host copy:

- `result_path` is the primary artifact path when known.
- `kwargs.run_dir` identifies the live Kit sidecar.
- `kwargs.run_toml` is a snapshot of Kit's manifest, including
  `output_dir`, `logs`, and `collect_dirs`.
- `kwargs.setup_logs` lists setup logs when Kit setup fails.

The snapshot lets `fetch` recover `output_dir` after the live `runs/`
tree has gone. `cancel` uses the live `run_dir` when available.

If Kit setup fails before an artifact exists, Queue may allocate the
client-shaped `.distsshqueue/<kind>/<stem>_<id8>/` leaf on the queue
host so the failed row remains fetchable. This is a fetch placeholder,
not a Kit artifact. Queue records all available setup log paths; it
does not choose a newest file and copy it as `setup_failure.log`.

## Client after fetch

The default destination is stable across Kit's timestamped leaf names:

```text
<client job project>/
  .distsshqueue/
    tickets/<uuid>                    qhost submit ticket
    <kind>/<stem>_<id8>/              one fetched job
      .distsshqueue-fetch-id          canonical job UUID
      ...                             primary artifact copy
      .distsshkit/
        logs/...                      Kit logs and setup logs
        collect/...                   Kit collect_dirs
```

`--into PATH` makes `PATH` itself the destination leaf. It may be
outside the client project. Fetch is additive: it does not delete
destination-only files. A nonempty destination without this job's
marker is refused unless `--force`.

The queue host resolves the source from the persisted row:

1. `result_path`
2. `kwargs.run_toml.output_dir`

It does not require that path to be under the job project or queue
store. If the primary path is absent but recorded extras still exist,
fetch skips the primary transfer and copies the extras. If neither a
primary nor extras exist, fetch is refused.

On the queue host, omit `qhost:` to print the persisted primary source
path without copying. See [fetch](@ref Queue-fetch) for command
syntax, retry rules, `--into`, and refusal cases.

## Staging is not output

`qhost:` submit copies the client project to
`~/.distsshqueue/stage/<uuid>` and leaves a ticket at
`.distsshqueue/tickets/<uuid>` on the client. The stage is the job
project used by Queue and Kit; the ticket is an identifier. Neither is
the result leaf.
