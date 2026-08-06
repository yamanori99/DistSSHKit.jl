#!/usr/bin/env bash
# Build once, then start docker-ssh workers (ports 2222 / 2223).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

./scripts/gen-keys.sh

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "docker compose not found" >&2
  exit 1
fi

# Build a single service so logs are not interleaved (both share the same image).
"${COMPOSE[@]}" -f compose.yml build worker-1
"${COMPOSE[@]}" -f compose.yml up -d --no-build
./scripts/wait-ready.sh
echo "Workers ready: distsshkit-w1 (2222), distsshkit-w2 (2223)"
echo "SSH config: ${ROOT}/.generated/ssh_config"
