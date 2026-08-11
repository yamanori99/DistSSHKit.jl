#!/usr/bin/env bash
# Build once, then start docker-ssh workers (ports 2222 / 2223).
# Optional: ./scripts/up.sh --e2e  → also run the SSH E2E suite from kit root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT_ROOT="$(cd "${ROOT}/../.." && pwd)"
RUN_E2E=0

for arg in "$@"; do
  case "$arg" in
    --e2e) RUN_E2E=1 ;;
    -h|--help)
      echo "usage: $0 [--e2e]"
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

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

if [[ "$RUN_E2E" -eq 1 ]]; then
  export DISTSSHKIT_SSH_E2E=1
  export DISTSSHKIT_YES=1
  cd "${KIT_ROOT}"
  exec julia --project=. --color=yes test/integration/ssh/run.jl
fi
