#!/bin/bash
# Container entrypoint: authorize mounted keys, install inter-worker identity, run sshd.
set -euo pipefail
SSH_DIR="/home/dev/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
IDENTITY="/mounted-keys/inter-worker"

if [[ ! -f "${IDENTITY}" || ! -f "${IDENTITY}.pub" ]]; then
    echo "start.sh: missing mounted-keys/inter-worker (and .pub); see testenv/docker-ssh/README.md" >&2
    exit 1
fi

# Docker Compose sets the UTS hostname. Apple container sets the network
# hostname from --name and keeps /proc/sys/kernel/hostname read-only, so
# do not write that file (start.sh would exit before sshd).
if [[ -n "${DISTSSHKIT_HOSTNAME:-}" ]]; then
    printf '%s\n' "${DISTSSHKIT_HOSTNAME}" > /etc/hostname
    grep -qw "${DISTSSHKIT_HOSTNAME}" /etc/hosts \
        || printf '127.0.1.1 %s\n' "${DISTSSHKIT_HOSTNAME}" >> /etc/hosts
fi

shopt -s nullglob
for key in /mounted-keys/*.pub; do
    line="$(tr -d '\n\r' < "${key}")"
    [[ -n "${line}" ]] || continue
    grep -qxF "${line}" "${AUTH_KEYS}" 2>/dev/null || echo "${line}" >> "${AUTH_KEYS}"
done
shopt -u nullglob

install -m 600 -o dev -g dev "${IDENTITY}" "${SSH_DIR}/id_ed25519"
install -m 644 -o dev -g dev "${IDENTITY}.pub" "${SSH_DIR}/id_ed25519.pub"

chmod 600 "${AUTH_KEYS}"
chown -R dev:dev "${SSH_DIR}"
exec /usr/sbin/sshd -D
