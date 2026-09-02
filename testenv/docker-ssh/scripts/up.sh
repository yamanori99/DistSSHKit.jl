#!/usr/bin/env bash
# Build once, then start docker-ssh workers (ports 2222 / 2223).
# Optional: ./scripts/up.sh --e2e  → also run the SSH E2E suite from kit root.
#
# CI: DISTSSHKIT_WORKER_IMAGE=ghcr.io/…:sha pulls instead of building.
# DISTSSHKIT_PUSH_IMAGE=… tags+pushes after a local build (retries for GHCR).
# DISTSSHKIT_SKIP_UP=1 skips compose up (image job: build+push only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT_ROOT="$(cd "${ROOT}/../.." && pwd)"
RUN_E2E=0
LOCAL_IMAGE="local/linux-ssh-worker:latest"

for arg in "$@"; do
  case "$arg" in
    --e2e) RUN_E2E=1 ;;
    -h|--help)
      echo "usage: $0 [--e2e]"
      echo "  DISTSSHKIT_WORKER_IMAGE  pull this tag (skip compose build)"
      echo "  DISTSSHKIT_PUSH_IMAGE    after build, tag and push (retried)"
      echo "  DISTSSHKIT_SKIP_UP=1     skip compose up (push-only)"
      echo "  DISTSSHKIT_CODE_COVERAGE=1  e2e with --code-coverage=user (child CLI too)"
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

pull_worker_image() {
  local image="$1"
  local retries="${DISTSSHKIT_WORKER_PULL_RETRIES:-1}"
  local attempt=1
  while true; do
    if docker pull "$image"; then
      docker tag "$image" "$LOCAL_IMAGE"
      return 0
    fi
    if (( attempt >= retries )); then
      echo "docker pull failed after ${retries} attempts: ${image}" >&2
      return 1
    fi
    echo "waiting for worker image (${attempt}/${retries}): ${image}" >&2
    sleep 15
    attempt=$((attempt + 1))
  done
}

if [[ -n "${DISTSSHKIT_WORKER_IMAGE:-}" ]]; then
  pull_worker_image "$DISTSSHKIT_WORKER_IMAGE"
else
  # Build a single service so logs are not interleaved (both share the same image).
  "${COMPOSE[@]}" -f compose.yml build child-1
  if [[ -n "${DISTSSHKIT_PUSH_IMAGE:-}" ]]; then
    DISTSSHKIT_LOCAL_IMAGE="$LOCAL_IMAGE" ./scripts/push-image.sh "$DISTSSHKIT_PUSH_IMAGE"
  fi
fi

if [[ "${DISTSSHKIT_SKIP_UP:-}" == "1" ]]; then
  echo "DISTSSHKIT_SKIP_UP=1: image ready, not starting workers"
  exit 0
fi

./scripts/down.sh
"${COMPOSE[@]}" -f compose.yml up -d --no-build
./scripts/wait-ready.sh
echo "Workers ready: distsshkit-w1 (2222), distsshkit-w2 (2223)"
echo "SSH config: ${ROOT}/.generated/ssh_config"

if [[ "$RUN_E2E" -eq 1 ]]; then
  export DISTSSHKIT_SSH_E2E=1
  export DISTSSHKIT_YES=1
  cd "${KIT_ROOT}"
  # WSL weekly has no julia-buildpkg. Fresh juliaup has no registries
  # (`Registry.update` then fails). linux/macOS already instantiated (no-op).
  julia --project=. --color=yes -e '
    using Pkg
    isempty(Pkg.Registry.reachable_registries()) && Pkg.Registry.add("General")
    Pkg.Registry.update()
    Pkg.resolve()
    Pkg.instantiate()
  '
  julia_e2e=(julia --project=. --color=yes)
  if [[ "${DISTSSHKIT_CODE_COVERAGE:-}" == "1" ]]; then
    julia_e2e+=(--code-coverage=user)
  fi
  e2e_status=0
  "${julia_e2e[@]}" test/e2e.jl || e2e_status=$?
  if [[ "$e2e_status" -eq 0 ]]; then
    "${ROOT}/scripts/down.sh"
  else
    echo "e2e failed (exit ${e2e_status}) — leaving workers up for debugging; ${ROOT}/scripts/down.sh to tear down" >&2
  fi
  exit "$e2e_status"
fi
