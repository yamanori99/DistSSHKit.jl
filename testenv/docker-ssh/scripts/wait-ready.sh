#!/usr/bin/env bash
# Wait until both docker-ssh workers accept BatchMode SSH and have Julia.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH_CONFIG="${ROOT}/.generated/ssh_config"
HOSTS=(distsshkit-w1 distsshkit-w2)
MAX_ATTEMPTS="${DISTSSHKIT_SSH_WAIT_ATTEMPTS:-60}"
SLEEP_SEC="${DISTSSHKIT_SSH_WAIT_SLEEP:-2}"

if [[ ! -f "${SSH_CONFIG}" ]]; then
  echo "missing ${SSH_CONFIG}; run scripts/gen-keys.sh first" >&2
  exit 1
fi

ssh_ok() {
  local host="$1"
  ssh -F "${SSH_CONFIG}" -o ConnectTimeout=5 "${host}" 'echo ok' >/dev/null 2>&1
}

julia_ok() {
  local host="$1"
  ssh -F "${SSH_CONFIG}" -o ConnectTimeout=5 "${host}" \
    'test -x /usr/local/bin/julia && /usr/local/bin/julia --version' >/dev/null 2>&1
}

for host in "${HOSTS[@]}"; do
  echo "Waiting for SSH on ${host}..."
  ok=0
  for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
    if ssh_ok "${host}"; then
      ok=1
      break
    fi
    sleep "${SLEEP_SEC}"
  done
  if [[ "${ok}" -ne 1 ]]; then
    echo "SSH not ready: ${host}" >&2
    exit 1
  fi
  if ! julia_ok "${host}"; then
    echo "Julia not ready on ${host}" >&2
    exit 1
  fi
  echo "  ${host}: ok"
done
