#!/usr/bin/env bash
# Start two Linux SSH workers with Apple `container` (same image/keys/aliases
# as docker-ssh). Optional: ./scripts/up.sh --e2e
#
# Writes testenv/docker-ssh/.generated/ssh_config so test/e2e.jl works unchanged.
# Do not run docker-ssh compose workers at the same time (shared ssh_config).
set -euo pipefail

APPLE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_ROOT="$(cd "${APPLE_ROOT}/../docker-ssh" && pwd)"
KIT_ROOT="$(cd "${APPLE_ROOT}/../.." && pwd)"
LOCAL_IMAGE="local/linux-ssh-worker:latest"
NAMES=(worker-1 worker-2)
RUN_E2E=0

for arg in "$@"; do
  case "$arg" in
    --e2e) RUN_E2E=1 ;;
    -h|--help)
      echo "usage: $0 [--e2e]"
      echo "  Same E2E as docker-ssh (distsshkit-w1 / distsshkit-w2)."
      echo "  Needs macOS 26+ Apple silicon and the container CLI."
      echo "  DISTSSHKIT_CODE_COVERAGE=1  e2e with --code-coverage=user"
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

if ! command -v container >/dev/null 2>&1; then
  echo "container CLI not found. Install https://github.com/apple/container" >&2
  exit 1
fi
if [[ "$(uname -s)" != "Darwin" ]] || [[ "$(uname -m)" != "arm64" ]]; then
  echo "apple-container-ssh is macOS Apple silicon only" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to read container inspect JSON" >&2
  exit 1
fi

container_ipv4() {
  local name="$1"
  container inspect "${name}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
nets = data[0].get("status", {}).get("networks") or []
if not nets:
    sys.exit(1)
addr = nets[0].get("ipv4Address") or ""
print(addr.split("/")[0])
'
}

write_ssh_config() {
  local ip1="$1" ip2="$2"
  local gen="${DOCKER_ROOT}/.generated"
  local ctrl="${gen}/controller"
  local kh="${gen}/known_hosts"
  mkdir -p "${gen}"
  umask 077
  cat > "${gen}/ssh_config" <<EOF
Host distsshkit-w1
  HostName ${ip1}
  User dev
  Port 22
  IdentityFile ${ctrl}
  IdentitiesOnly yes
  BatchMode yes
  ConnectTimeout 10
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${kh}
  ServerAliveInterval 60
  ServerAliveCountMax 10
  TCPKeepAlive yes

Host distsshkit-w2
  HostName ${ip2}
  User dev
  Port 22
  IdentityFile ${ctrl}
  IdentitiesOnly yes
  BatchMode yes
  ConnectTimeout 10
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${kh}
  ServerAliveInterval 60
  ServerAliveCountMax 10
  TCPKeepAlive yes
EOF
}

inject_worker_hosts() {
  local ip1="$1" ip2="$2"
  local cfg="${DOCKER_ROOT}/.generated/ssh_config"
  # Apple default network does not resolve peer names; e2e git uses dev@worker-1.
  ssh -F "${cfg}" distsshkit-w1 \
    "grep -q ' worker-2\$' /etc/hosts || echo '${ip2} worker-2' | sudo tee -a /etc/hosts >/dev/null"
  ssh -F "${cfg}" distsshkit-w2 \
    "grep -q ' worker-1\$' /etc/hosts || echo '${ip1} worker-1' | sudo tee -a /etc/hosts >/dev/null"
}

echo "Starting container system (no-op if already up)..."
container system start

"${DOCKER_ROOT}/scripts/gen-keys.sh"

if ! container image ls | grep -q "local/linux-ssh-worker"; then
  echo "Building ${LOCAL_IMAGE} from docker-ssh/Dockerfile..."
  (cd "${DOCKER_ROOT}" && container build -t "${LOCAL_IMAGE}" .)
fi

"${APPLE_ROOT}/scripts/down.sh"
MOUNT="type=bind,source=${DOCKER_ROOT}/mounted-keys,target=/mounted-keys,readonly"
# Sized to match one ubuntu-latest CI runner shared by both workers (2 CPU / 7GB).
WORKER_CPUS="${DISTSSHKIT_APPLE_WORKER_CPUS:-1}"
WORKER_MEMORY="${DISTSSHKIT_APPLE_WORKER_MEMORY:-3584M}"
for name in "${NAMES[@]}"; do
  container create -d --name "${name}" --network default \
    -c "${WORKER_CPUS}" -m "${WORKER_MEMORY}" \
    -u root --mount "${MOUNT}" "${LOCAL_IMAGE}"
  container start "${name}"
done

echo "Waiting for worker IPs..."
IP1="" IP2=""
for ((i = 1; i <= 30; i++)); do
  IP1="$(container_ipv4 worker-1 2>/dev/null || true)"
  IP2="$(container_ipv4 worker-2 2>/dev/null || true)"
  if [[ -n "${IP1}" && -n "${IP2}" ]]; then
    break
  fi
  sleep 1
done
if [[ -z "${IP1}" || -z "${IP2}" ]]; then
  echo "workers have no IPv4 yet; container ls:" >&2
  container ls >&2
  exit 1
fi

write_ssh_config "${IP1}" "${IP2}"
echo "Workers: distsshkit-w1 -> ${IP1}:22  distsshkit-w2 -> ${IP2}:22"
echo "SSH config: ${DOCKER_ROOT}/.generated/ssh_config"

"${DOCKER_ROOT}/scripts/wait-ready.sh"
inject_worker_hosts "${IP1}" "${IP2}"
echo "Inter-worker DNS: worker-1 / worker-2 in each /etc/hosts"
# First peer SSH needs accept-new (BatchMode cannot prompt). Same as e2e git warmup.
ssh -F "${DOCKER_ROOT}/.generated/ssh_config" distsshkit-w1 \
  "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR -o ConnectTimeout=5 dev@worker-2 true"
ssh -F "${DOCKER_ROOT}/.generated/ssh_config" distsshkit-w2 \
  "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR -o ConnectTimeout=5 dev@worker-1 true"

if [[ "$RUN_E2E" -eq 1 ]]; then
  export DISTSSHKIT_SSH_E2E=1
  export DISTSSHKIT_YES=1
  cd "${KIT_ROOT}"
  julia_e2e=(julia --project=. --color=yes)
  if [[ "${DISTSSHKIT_CODE_COVERAGE:-}" == "1" ]]; then
    julia_e2e+=(--code-coverage=user)
  fi
  e2e_status=0
  "${julia_e2e[@]}" test/e2e.jl || e2e_status=$?
  if [[ "$e2e_status" -eq 0 ]]; then
    "${APPLE_ROOT}/scripts/down.sh"
  else
    echo "e2e failed (exit ${e2e_status}) — leaving workers up for debugging; ${APPLE_ROOT}/scripts/down.sh to tear down" >&2
  fi
  exit "$e2e_status"
fi
