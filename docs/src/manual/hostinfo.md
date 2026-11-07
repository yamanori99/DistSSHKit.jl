# [hostinfo](@id Manual-hostinfo)

Show host identity, RAM, CPU, OS, and `julia --version`. Does **not**
start a job and does **not** recommend a worker count. Missing fields
print as `-`, not `0`. Collection is DistSSHBase `HostFacts` (public,
not reexported). Printing is DistSSHRun `print_hostinfo` (public, not
reexported).

```bash
julia --project=. -m DistSSHKit hostinfo [options] [parent] [child:NAME...]
```

Also: [pool](@ref Manual-pool), `help hostinfo`. Flag vocabulary:
[User Guide](@ref Manual). Queue has no `hostinfo` and does not forward
`qhost hostinfo` as a special inspect verb.

A reachable host with missing Julia is still ok (exit 0). A failed host
still gets a row; other hosts still print; the command exits 1.
Requested rows go to stdout, including `--quiet`.

## Flags

- `parent`: include this job's DistSSHKit parent (same token as `go` /
  `drive`; `:N` stripped)
- `--julia PATH`: remote Julia (default: auto-detect)
- `--hosts CSV`: comma-separated SSH hosts (`child:NAME:N` → host name
  only)
- `--hosts-file PATH`: append SSH hosts (`child:NAME:N` → host name only)
- `-q` / `--quiet`, `--progress`, `--verbose`
- `-v` / `--version`: print DistSSHKit version and exit
- `-h` / `--help`: full help

`--probe`, `--gb-per-worker`, `--mem-headroom`, `--parent-gb`, and
`--master-gb` are errors. Worker counts stay explicit `parent:N` /
`child:NAME:N`.

```bash
julia --project=. -m DistSSHKit hostinfo parent child:host1 child:host2
```
