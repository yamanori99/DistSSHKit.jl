# [fetch](@id Queue-fetch)

Copy one finished Kit result leaf onto this job tree. Inverse of
`qhost:` stage (Kit rsync excludes: `.gitignore`, `.git/`, `.distsshkit/`,
`.distsshqueue/`). `qhost:` submit leaves
`.distsshqueue/tickets/<uuid>` on this tree (one file per job, kept).
That file is not the Kit leaf.
For the ownership boundary and both directory trees, see
[Artifacts and paths](@ref Queue-artifacts).

```bash
julia --project=. -m DistSSHQueue [qhost:HOST] fetch <id>  # 8-char prefix or full UUID
julia --project=. -m DistSSHQueue [qhost:HOST] fetch .distsshqueue/tickets/<uuid>
```

Also: [First job](@ref Queue-Tutorial-Client), [Walkthrough](@ref Queue-Tutorial-Walkthrough),
[submit](@ref Queue-submit),
[status](@ref Queue-status).

Run it from the same `cwd` / `DISTRIBUTED_PROJECT_ROOT` as `submit`.

## Destination

- Default:
  `{project}/.distsshqueue/{go|ride|drive}/{stem}_{id8}/`
- With `--into PATH`: `PATH` itself, with no extra
  `{stem}_{id8}` directory
- stdout: the destination path, one line

`--into` may point outside the job project. The destination is not the
Kit source under `{project}/.distsshkit/{kind}/…`.

## Existing destination

One destination holds one job:

- A matching `.distsshqueue-fetch-id` makes a repeat fetch skip rsync
  and print `already fetched`.
- `--force` repeats the copy.
- A nonempty destination without a matching marker is refused unless
  `--force`.
- The copy is additive. Destination-only files remain; same-name
  source files replace their destination copies.

The marker stores the canonical job UUID, so an 8-character prefix
still matches it.

## Extra files

`qhost:` fetch copies more than the primary artifact:

- Kit `logs` and recorded setup logs go to `.distsshkit/logs/`.
- Kit `collect_dirs` go to `.distsshkit/collect/`.

The transfer prints `rsync ← HOST:…` on stderr.
`DISTSSHKIT_QUIET` hides that line.

## On the queue host

Omit `qhost:` to print the source path without copying. The source is
the persisted `result_path` or `run.toml` `output_dir`; it may be
outside the job project.

Failed and cancelled jobs are fetchable when a primary artifact or
recorded extra exists. If Kit `setup!` failed before `execute!`, the
row contains setup `*.log` paths in `setup_logs`; Queue does not create
`setup_failure.log`.

The argument may be a ticket path, full UUID, or unique 8-character
prefix from `status`.

`fetch` stays on the client. It does not hop `main` (`status` /
`cancel` do). Path lookup is a captured `julia -e` on the queue host
(same hop as stage homedir).

## Flags

| Flag | Meaning |
| --- | --- |
| `<id>` | Unique 8-character prefix (`status`) or the full UUID (`submit` stdout) |
| ticket | `.distsshqueue/tickets/<uuid>` (same job; no need to copy stdout) |
| `--into PATH` | Dest directory (the leaf). Relative to the job project; absolute paths may be outside it. One job per dest |
| `--force` | Copy even if dest already has this or another job. Does not delete dest-only files |
| `--progress` | `qhost:` rsync `--info=progress2` (`DISTSSHKIT_PROGRESS`) |
| `-h` / `--help` | Queue usage |

No `--output-dir`. Kit worker collect is not repeated.

## Refused

`:queued`, `:running`, and a row with no Kit `output_dir` / `result_path`
and no recorded extras. Source is the persisted job (`run.toml` snapshot
or `result_path`), not a client-side path check. Dest is still
`{kind}/{stem}_{id8}` unless `--into`.
