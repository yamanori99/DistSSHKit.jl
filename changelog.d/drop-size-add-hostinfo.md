category: breaking

- Remove CLI `size` / Julia `size!`, RSS probes, and worker-count
  estimates. `WorkerPlan` stays for explicit `head_workers` and `N*host`
  machine tokens.
  `hostinfo` is DistSSHRun only (`HostFacts` /
  `collect_host_facts` in DistSSHBase). Queue does not forward `hostinfo`.
  `pool` stays factual cores / RAM / reachability. Missing facts print as
  `-`, not `0`. Point `[sources]` at the matching DistSSHRun and
  DistSSHQueue branches until those land on `main`.
