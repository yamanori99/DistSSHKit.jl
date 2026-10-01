#!/usr/bin/env bash
# Stop and remove docker-ssh workers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "docker compose not found" >&2
  exit 1
fi

# Previous container_name was distsshkit-child-*. Drop it so port 2222 is free.
if command -v docker >/dev/null 2>&1; then
  docker rm -f distsshkit-child-1 distsshkit-child-2 >/dev/null 2>&1 || true
fi

"${COMPOSE[@]}" -f compose.yml down --remove-orphans
