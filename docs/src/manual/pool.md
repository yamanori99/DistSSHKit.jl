# [pool](@id Manual-pool)

Show the listed machines as one cluster: cores, RAM, a slot hint, and
whether each host answered. Does **not** start a job. Unreachable listed
hosts stay in the list and the command fails (fail-closed). It does not
drop a dead node and continue the way `--best-effort` can on drive.

```bash
julia --project=. -m DistSSHKit pool [options] [parent] [child:NAME...]
```

Also: [size](@ref Manual-size), `pool --help`. API: [`pool!`](@ref).

Flag vocabulary: [User Guide](@ref Manual).

## Flags

- `parent`: include this job's DistSSHKit parent (`:N` stripped)
- `--gb-per-worker N`: GB per slot for the hint (default `1.5`; no RSS)
- `--mem-headroom N`: fraction of RAM usable for slots (default `0.75`)
- `--parent-gb N`: GB reserved for the parent process (default `0.4`)
- `--hosts CSV` / `--hosts-file PATH`: same tokens as size (`:N` stripped)
- `-q` / `--quiet`, `--progress`, `--verbose`
- `-v` / `--version`, `-h` / `--help`

[`size`](@ref Manual-size) still owns RSS probes (`--probe` / `size!`).
`pool` only reads OS cores and RAM (SSH for remotes). Dynamic join/leave
is not in this command.
