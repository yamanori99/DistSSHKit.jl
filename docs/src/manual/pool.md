# [pool](@id Manual-pool)

Show the listed machines as one cluster: cores, RAM, and whether each
host answered. Does **not** start a job. Does not recommend a worker
count. Unreachable listed hosts stay in the list and the command fails
(fail-closed). It does not drop a dead node and continue the way
`--best-effort` can on drive. Missing facts print as `-`, not `0`.

```bash
julia --project=. -m DistSSHKit pool [options] [parent] [child:NAME...]
```

Also: [hostinfo](@ref Manual-hostinfo), `help pool`. API: [`pool!`](@ref).

Flag vocabulary: [User Guide](@ref Manual).

## Flags

- `parent`: include this job's DistSSHKit parent (`:N` stripped)
- `--hosts CSV` / `--hosts-file PATH`: `parent` / `child:NAME[:N]`
  (`:N` stripped)
- `-q` / `--quiet`, `--progress`, `--verbose`
- `-v` / `--version`, `-h` / `--help`

`--probe`, `--gb-per-worker`, `--mem-headroom`, `--parent-gb`, and
`--master-gb` are errors. [`hostinfo`](@ref Manual-hostinfo) prints
identity / Julia facts. `pool` only reads OS cores and RAM (SSH for
remotes). Dynamic join/leave is not in this command.
