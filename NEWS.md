<!-- markdownlint-configure-file { "MD024": { "siblings_only": true } } -->

# News

User-facing changes.
GitHub Releases may copy these sections (`Release notes:` on
`@JuliaRegistrator register`).
Releases through 0.9.0 are in [HISTORY.md](HISTORY.md).

## Unreleased

- `setup --delete`, `setup --prune`, and `teardown` delete only when
  `--confirm-path` matches the computed path. Without it they print
  `Would remove` and exit 0. A path that contains `~` is shown in single
  quotes. `-y` and `DISTSSHKIT_YES` do not authorize those three.
- `julia -m DistSSHKit -v` prints two lines: this package, then
  DistSSHRun and DistSSHQueue.
- `setup --delete` and `setup --clone` refuse `~`, `/`, and a single
  directory under `/`.
- `setup --clone` also refuses when the git root would land on one of those.
- An SSH name that starts with `-` is rejected.
- `DISTRIBUTED_SSH_OPTS` is split with shell quoting. A quoted value that
  contains spaces stays one argument. An unmatched quote is an error. A
  non-empty value still replaces the default options.
- `detect_julia_path` throws when the SSH connection itself fails. That
  failure is not cached. A host whose shell ran and has no Julia still
  returns nothing.

## 0.10.0

- Breaking cut after `0.9.0`. Users add DistSSHKit. It depends on
  DistSSHRun and DistSSHQueue and reexports their public names.

### Breaking

- DistSSHKit depends on DistSSHRun and DistSSHQueue and reexports their
  public names. Private names stay in the package that defines them.
- `julia -m DistSSHKit` keeps `setup`, `up`, `go`, `ride`, `drive`,
  `plan`, `size`, `pool`, `demo`, and `progress`.
- Client commands (`submit`, `status`, `watch`, `cancel`, `fetch`,
  `list-host`, `stop`, `teardown`) take an optional `qhost:HOST`.
- Queue-host commands are `qhost setup`, `qhost up`, `qhost add-host`,
  `qhost remove-host`, `qhost serve`, `qhost stop`, `qhost enable`,
  `qhost disable`, `qhost teardown`, plus `qhost size` / `qhost plan` /
  `qhost pool` on that machine (#420).
- `service` stays a route: `service -h` says it is gone. Root help does not
  list it.
- `ride` compares a rewritten `map` / `filter`, including values from
  an indexed `for`, to a sequential run only when the caller passes
  `--spi-check` / `spi_check=true`.
- `ride!` and `execute!(:ride)` default `spi_check=false`.
- Detached `execute!` passes `--spi-check` when that keyword is true and
  `--no-spi-check` when it is false, so an older child does not fall back
  to its own default (#421).
- The experimental `distsshkit` command (`pkg> app add DistSSHKit`) is gone.
  If you installed it, run `pkg> app rm DistSSHKit`.
  Call DistSSHKit with `julia -m DistSSHKit`.
  Removing that public entry is breaking.
