# [hostinfo](@id Manual-hostinfo)

Show host identity, RAM, CPU, OS, and `julia --version`. Does **not**
start a job and does **not** recommend a worker count. Missing fields
print as `-`, not `0`. Collection is DistSSHBase `HostFacts` (public,
not reexported). Printing is DistSSHRun `print_hostinfo` (public, not
reexported).

```bash
julia --project=. -m DistSSHKit hostinfo [options] [parent] [HOST...]
```

Also: [pool](@ref Manual-pool), `help hostinfo`. Flag vocabulary:
[User Guide](@ref Manual). Queue has no `hostinfo` and does not forward
`qhost hostinfo` as a special inspect verb.

A reachable host with missing Julia is still ok (exit 0). A failed host
still gets a row; other hosts still print; the command exits 1.
Requested rows go to stdout, including `--quiet`.

## Flags

- `parent`: include the head row ([`is_parent_host_name`](@ref); not an SSH
  Host name)
- `--julia PATH`: remote Julia (default: auto-detect)
- `--hosts CSV`: comma-separated SSH host names (`N*host` counts stripped)
- `--hosts-file PATH`: append SSH host names (`N*host` counts stripped)
- `-q` / `--quiet`, `--progress`, `--verbose`
- `-v` / `--version`: print DistSSHKit version and exit
- `-h` / `--help`: full help

`--probe`, `--gb-per-worker`, `--mem-headroom`, `--parent-gb`, and
`--master-gb` are errors. Placement on `go` / `drive` / `ride` uses
`N*host` and `--head-workers` / `--head-slots`, not this command.

```bash
julia --project=. -m DistSSHKit hostinfo parent host1 host2
```
