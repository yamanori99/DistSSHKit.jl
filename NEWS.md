<!-- markdownlint-configure-file { "MD024": { "siblings_only": true } } -->

# News

User-facing changes.
GitHub Releases use the notes on `@JuliaRegistrator register`.
Those notes are often shorter than the section below.
Releases through 0.9.0 are in [HISTORY.md](HISTORY.md).

## Unreleased

### Planned breaking (next minor)

- `terminate!` / `terminate_run!` `interrupt_grace` will default to a positive value, so a stop sends SIGINT before SIGTERM. `cancel` of a running job will use that default. Until then the default is `0` and `cancel` does not send SIGINT. DistSSHKit 0.11 (DistSSHRun 0.2, DistSSHQueue 0.10).
- `-y`, `--yes`, and `DISTSSHKIT_YES` will stop authorizing
  `setup --delete`, `setup --prune`, and `teardown`. Without
  `--confirm-path`, `-y` will exit 1. A `teardown` that was not asked to
  delete still prints `Would remove` and exits 0. `up default` still
  honors `DISTSSHKIT_YES`. DistSSHKit 0.11 (DistSSHRun 0.2, DistSSHQueue 0.10).
  `KitSession` `yes=true` is outside this change. `setup!(session, :delete)`
  and `setup!(session, :prune)` without `confirm_path` still follow `session.yes`.
- `rsync_send_list` will stop being reexported. It stays public on
  DistSSHRun. DistSSHKit 0.11.
- Names DistSSHRun 0.2 stops exporting will stop being reexported.
  `parse_go_args`, `parse_drive_args`, and `parse_ride_args` stay.
  DistSSHKit 0.11 (DistSSHRun 0.2).

## 0.10.5

- Requires DistSSHRun 0.1.14 and DistSSHQueue 0.9.8.
- The manual distinguishes `add-host` and `pool`, which compare a worker with serve's Julia, from `setup --check`, which warns on a patch or a prerelease and returns those warnings from `setup!`. It also describes the `submit`, `status`, and `qhost:` `fetch` lines DistSSHQueue 0.9.8 already prints.

## 0.10.4

- A name that DistSSHRun or DistSSHQueue marks public, and does not export, is not reexported. `rsync_send_list` stays reexported until 0.11. The current export set is unchanged.

## 0.10.3

- The logo is an original fan. The Julia-circle exception is gone, so the package is MIT only.
- Requires DistSSHRun 0.1.10 and DistSSHQueue 0.9.7.
- The first `julia -m DistSSHKit` compiles the `main` of the package it calls. Commands, flags, and exit codes are unchanged.

## 0.10.2

- Requires DistSSHRun 0.1.9 and DistSSHQueue 0.9.6.
- `dist_ssh_kit_version` is exported.
- `--project` placed after `julia -m DistSSHKit` exits 1 with `Error:`.
  Put it before `-m`: `julia --project=DIR -m DistSSHKit …`. Routing of
  other arguments is unchanged.
- Host SSH and juliaup come from DistSSHRun 0.1.7 (`DistSSHBase` and
  `DistSSHUp`). The copies in this package are gone. DistSSHRun compat is
  `0.1.9`. DistSSHQueue compat is `0.9.6`.
- `setup --rsync` inside one git repository also applies `.gitignore`
  files above the send root. That has been true since DistSSHRun 0.1.7.
  A `qhost:` stage in a git work tree sends that same file list.
  `.distsshqueue/` stays out. Outside git, rsync still uses each
  directory's `.gitignore`.
- CLI flags, confirmation, and exit codes are unchanged.

## 0.10.1

- Requires DistSSHRun 0.1.6 and DistSSHQueue 0.9.4.
- `setup!(session, :delete; confirm_path)` and `setup!(session, :prune; confirm_path)` delete when that path matches, even when `yes=false`. Omitting `confirm_path` still follows `session.yes`. Other modes reject `confirm_path`.
- `setup --delete` and `setup --prune` delete when `--confirm-path` matches the computed path. A mismatch names that path in single quotes and exits 1. Without `--confirm-path`, `-y` and `DISTSSHKIT_YES` still skip the prompt and delete. That skip stops in DistSSHKit 0.11 (DistSSHRun 0.2). With neither, they ask for `delete` or `prune`.
- `teardown` deletes when every existing path is passed with `--confirm-path`. Without that it prints `Would remove` and exits 0. `-y` and `DISTSSHKIT_YES` (process or config `[env]`) still delete. That skip stops in DistSSHKit 0.11 (DistSSHQueue 0.10).
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
