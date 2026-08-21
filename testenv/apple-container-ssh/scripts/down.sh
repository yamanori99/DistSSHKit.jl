#!/usr/bin/env bash
# Stop and remove Apple-container workers (leave buildkit alone).
set -euo pipefail

if ! command -v container >/dev/null 2>&1; then
  echo "container CLI not found (Apple container)" >&2
  exit 1
fi

for name in worker-1 worker-2; do
  container stop "${name}" >/dev/null 2>&1 || true
  container rm "${name}" >/dev/null 2>&1 || true
done
echo "Removed worker-1 and worker-2 (if they existed)"
