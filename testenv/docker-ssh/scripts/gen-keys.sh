#!/usr/bin/env bash
# Generate kit-parent + inter-worker keys and SSH config for docker-ssh workers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS="${ROOT}/mounted-keys"
GEN="${ROOT}/.generated"
CONTROLLER_KEY="${GEN}/controller"
SSH_CONFIG="${GEN}/ssh_config"
HOSTS_FILE="${GEN}/hosts"

mkdir -p "${KEYS}" "${GEN}"

if [[ ! -f "${CONTROLLER_KEY}" ]]; then
  ssh-keygen -t ed25519 -f "${CONTROLLER_KEY}" -N "" -C "distsshkit-docker-ssh-controller"
fi
cp "${CONTROLLER_KEY}.pub" "${KEYS}/controller.pub"

if [[ ! -f "${KEYS}/inter-worker" ]]; then
  ssh-keygen -t ed25519 -f "${KEYS}/inter-worker" -N "" -C "distsshkit-inter-worker"
fi

umask 077
cat > "${SSH_CONFIG}" <<EOF
Host child-1
  HostName 127.0.0.1
  User dev
  Port 2222
  IdentityFile ${CONTROLLER_KEY}
  IdentitiesOnly yes
  BatchMode yes
  ConnectTimeout 10
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${GEN}/known_hosts
  ServerAliveInterval 60
  ServerAliveCountMax 10
  TCPKeepAlive yes

Host child-2
  HostName 127.0.0.1
  User dev
  Port 2223
  IdentityFile ${CONTROLLER_KEY}
  IdentitiesOnly yes
  BatchMode yes
  ConnectTimeout 10
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ${GEN}/known_hosts
  ServerAliveInterval 60
  ServerAliveCountMax 10
  TCPKeepAlive yes
EOF

cat > "${HOSTS_FILE}" <<'EOF'
# DistSSHKit docker-ssh children (SSH Host, hostname, peer DNS)
child-1
child-2
EOF

echo "Wrote ${SSH_CONFIG}"
echo "Wrote ${HOSTS_FILE}"
echo "Kit parent pub → ${KEYS}/controller.pub"
