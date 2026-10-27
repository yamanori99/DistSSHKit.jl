category: planned

- `terminate!` / `terminate_run!` `interrupt_grace` will default to a positive value, so a stop sends SIGINT before SIGTERM. `cancel` of a running job will use that default. Until then the default is `0` and `cancel` does not send SIGINT. DistSSHKit 0.11 (DistSSHRun 0.2, DistSSHQueue 0.10).
