# Apple container SSH workers (macOS, optional)

Linux SSH workers on a Mac via Apple
[`container`](https://github.com/apple/container). Same image, keys, and
`distsshkit-w1` / `distsshkit-w2` aliases as [`../docker-ssh`](../docker-ssh),
so [`test/e2e.jl`](../../test/e2e.jl) is unchanged.

**Not CI and not `Pkg.test()`.** Compose path stays the default for GitHub
and for Linux / Docker Desktop / WSL.

Do not run `docker-ssh` compose workers at the same time: both write
`docker-ssh/.generated/ssh_config`.

## Requirements

- macOS 26+, Apple silicon
- [`container`](https://github.com/apple/container) CLI
- `python3` (reads `container inspect` JSON)

## Local use

From this directory (kit root also works if you keep the path):

```bash
./scripts/up.sh --e2e    # workers + suite
./scripts/up.sh          # workers only
./scripts/down.sh
```

Each `up.sh` runs `container system start` and rebuilds
`local/linux-ssh-worker:latest` from
[`../docker-ssh/Dockerfile`](../docker-ssh/Dockerfile)
with juliaup channels from `.github/julia-slots.env` (same as Compose).
Layer cache if the file is unchanged. Then it removes and recreates
`child-1` / `child-2`.
Keys come from `docker-ssh/scripts/gen-keys.sh` (mounted from
`docker-ssh/mounted-keys`).

Each worker gets 1 CPU / 3.5GB (`DISTSSHKIT_APPLE_WORKER_CPUS` /
`DISTSSHKIT_APPLE_WORKER_MEMORY` override), so the pair together matches one
`ubuntu-latest` CI runner (2 CPU / 7GB).

SSH aliases after `up.sh`:

- `distsshkit-w1` → worker IP, port 22, user `dev`
- `distsshkit-w2` → the other worker

```bash
ssh -F ../docker-ssh/.generated/ssh_config distsshkit-w1 \
  'echo ok; julia --version'
```

Apple’s default network does not resolve `child-1` / `child-2` between
containers. `up.sh` appends those names to each child `/etc/hosts` so git
E2E (`dev@child-1`) matches Compose DNS.

## Manual smoke (no E2E)

`./scripts/up.sh` is enough. `container exec` has no `--` (that flag is Docker):

```bash
container exec -it -u dev child-1 bash -l
```

## Teardown

```bash
./scripts/down.sh
```

Leaves `buildkit` and the image. Optional:

```bash
container image rm local/linux-ssh-worker:latest
```

Switch back to Docker: `docker-ssh/scripts/up.sh` rewrites `ssh_config` to
`127.0.0.1:2222` / `2223`.

## Troubleshooting

- `container CLI not found`: install Apple `container`, then retry
- `apiserver is not running`: `container system start` (also done by
  `up.sh`)
- `dockerfile not found`: run `up.sh` from this `scripts/` tree
- `401` pulling the worker image: let `up.sh` build, or build in
  `../docker-ssh`
- SSH timeout: `container ls`; empty IP → `container start` or `up.sh`
- Host key failed / changed: `up.sh` uses `accept-new` and docker-ssh
  `known_hosts`
- git E2E cannot clone `dev@child-1`: re-run `up.sh` (injects
  `/etc/hosts`)
