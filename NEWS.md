<!-- markdownlint-configure-file { "MD024": { "siblings_only": true } } -->

# News

User-facing changes.
GitHub Releases may copy these sections (`Release notes:` on
`@JuliaRegistrator register`).
Releases through 0.9.0 are in [HISTORY.md](HISTORY.md).

## Unreleased

### Breaking

- DistSSHKit depends on DistSSHRun and DistSSHQueue and reexports their
  public names. Private names stay in the package that defines them.
  `julia -m DistSSHKit` keeps `setup`, `up`, `go`, `ride`, `drive`,
  `plan`, `size`, `pool`, `demo`, and `progress`. Client commands
  (`submit`, `status`, `watch`, `cancel`, `fetch`, `list-host`, `stop`,
  `teardown`) take an optional `qhost:HOST`. Queue-host commands are
  `qhost setup`, `qhost up`, `qhost add-host`, `qhost remove-host`,
  `qhost serve`, `qhost stop`, `qhost enable`, `qhost disable`,
  `qhost teardown`, plus `qhost size` / `qhost plan` / `qhost pool` on
  that machine (#420). `service` stays a route: `service -h` says it is
  gone. Root help does not list it.
- DistSSHBase and DistSSHUp are no longer dependencies. Host talking and
  juliaup verbs live in this package's `base/` and `up/`.
- `ride` compares a rewritten `map` / `filter`, including values from
  an indexed `for`, to a sequential run only when the caller passes
  `--spi-check` / `spi_check=true`. `ride!` and `execute!(:ride)`
  default `spi_check=false`. Detached `execute!` passes `--spi-check` when
  that keyword is true and `--no-spi-check` when it is false, so an older
  child does not fall back to its own default (#421).
