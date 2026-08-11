# Apple container SSH workers (macOS, optional)

Manual Linux workers on a Mac via Apple
[`container`](https://github.com/apple/container). **Not used by CI or
`Pkg.test()`.**

CI and Docker Desktop / Linux hosts: [`../docker-ssh`](../docker-ssh)
(same image: `../docker-ssh/Dockerfile`).

Two Ubuntu 24.04 nodes as user `dev`: Mac → worker SSH, and worker → worker SSH
(shared `mounted-keys/inter-worker`).

Work from this directory. Placeholder `WORKER_IP` / `WORKER_2_IP` means the IP
from `container ls` with the `/24` suffix removed. Never paste the literal
string `WORKER_IP`.

## Requirements

- macOS 26+, Apple silicon
- `container system start`

## Setup

### 1. Build

Image lives under `docker-ssh` (shared with Compose / CI):

```bash
cd testenv/docker-ssh
container build -t local/linux-ssh-worker:latest .
cd ../apple-container-ssh
```

Build before `create`, or the CLI tries Docker Hub and fails.

### 2. Keys

`mounted-keys/` is gitignored. Required:

| File | Role |
| --- | --- |
| `controller.pub` | Mac → worker |
| `inter-worker`, `inter-worker.pub` | worker → worker |

```bash
cp "${HOME}/.ssh/id_ed25519.pub" mounted-keys/controller.pub 2>/dev/null \
    || cp "${HOME}/.ssh/id_rsa.pub" mounted-keys/controller.pub

ssh-keygen -t ed25519 -f mounted-keys/inter-worker -N ""
```

Missing `inter-worker` (+ `.pub`) makes the container exit on start.

### 3. Create and start

```bash
MOUNT="type=bind,source=$(pwd)/mounted-keys,target=/mounted-keys,readonly"

container create -d --name worker-1 --network default \
    -u root --mount "${MOUNT}" local/linux-ssh-worker:latest
container create -d --name worker-2 --network default \
    -u root --mount "${MOUNT}" local/linux-ssh-worker:latest

container start worker-1
container start worker-2
container ls
```

`-u root` is for the init process only. Log in as `dev@WORKER_IP`. Empty IP →
`container start <name>`.

## Test

### Mac → worker

First batch connect needs `StrictHostKeyChecking=accept-new` (with
`BatchMode=yes`, SSH cannot prompt for a new host key):

```bash
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    dev@WORKER_IP 'echo ok'
ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    dev@WORKER_IP '~/.juliaup/bin/julia --version'
```

Interactive shell (no `-it`; that flag is for `container exec`):

```bash
ssh dev@WORKER_IP
```

From that shell, worker → worker is `ssh dev@WORKER_2_IP` (same shared key).

Without SSH, from the Mac (no `--`; Docker-only):

```bash
container exec -it -u dev worker-1 bash -l
```

### DistSSHKit (optional)

From the DistSSHKit kit root on the Mac (after workers are up and you have SSH
aliases or `dev@WORKER_IP`):

```bash
# Path resolve smoke (controller Darwin + remote Linux) — not CI.
julia --project=. -e '
using DistSSHKit
ctrl = DistSSHKit.resolve_controller_julia("auto")
@assert isabspath(ctrl) && isfile(ctrl)
println("controller: ", ctrl)
# Replace HOST with distsshkit-w1 or dev@WORKER_IP
host = get(ENV, "DISTSSHKIT_APPLE_HOST", "dev@WORKER_IP")
found = DistSSHKit.resolve_remote_julia(host, "auto")
@assert found !== nothing && found != "julia"
println("remote: ", found, " ", DistSSHKit.get_remote_julia_version(host, found))
'

julia --project=. -m DistSSHKit setup --check --julia auto HOST
```

Do not treat this as CI coverage. Free GitHub runners cannot host Mac workers.

## Teardown

One name per command. Leave `buildkit` alone.

```bash
container stop worker-1
container stop worker-2
container rm worker-1
container rm worker-2
```

### Keys

Leave `.gitkeep`. Stop/rm workers first if they are still running.

```bash
rm -f mounted-keys/controller.pub \
      mounted-keys/inter-worker \
      mounted-keys/inter-worker.pub
```

Also remove any extra `*.pub` you added. Only `.gitkeep` should remain.

### Image and known_hosts (optional)

```bash
container image rm local/linux-ssh-worker:latest   # after containers are gone
ssh-keygen -R WORKER_IP                            # each real worker IP
```

Rebuild after Dockerfile changes: teardown → build under `docker-ssh` → keys →
create → start. Run `ssh-keygen -R` if SSH warns about a changed host key.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| `dockerfile not found` / `context dir does not exist` | `cd testenv/docker-ssh`, then `container build … .` |
| `401` pulling `linux-ssh-worker` | Build `local/linux-ssh-worker:latest` first |
| `container already exists` | `container start <name>`, or teardown then recreate |
| `not found` on stop/rm | Already gone — check `container ls` |
| `path … is not a directory` on create | Mount `mounted-keys/`, not a single `*.pub` |
| Missing `inter-worker` / start fails | Create keys (Setup §2), then recreate workers |
| Password prompt worker → worker | Same as above |
| `Host key verification failed` | Add `-o StrictHostKeyChecking=accept-new`, or interactive `ssh` once |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | `ssh-keygen -R WORKER_IP` (real IP) |
