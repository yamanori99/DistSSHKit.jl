category: breaking

- Remove CLI `size` / Julia `size!`, RSS probes, and worker-count
  estimates. `WorkerPlan` stays for explicit `parent:N` / `child:NAME:N`.
  `hostinfo` is DistSSHRun only (`HostFacts` /
  `collect_host_facts` in DistSSHBase). Queue does not forward `hostinfo`.
  `pool` stays factual cores / RAM / reachability. Missing facts print as
  `-`, not `0`. Point `[sources]` at the matching DistSSHRun and
  DistSSHQueue branches until those land on `main`.
