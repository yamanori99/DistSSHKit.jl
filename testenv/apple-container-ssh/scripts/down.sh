#!/usr/bin/env bash
# Stop and remove Apple-container SSH children (leave buildkit alone).
set -euo pipefail

if ! command -v container >/dev/null 2>&1; then
  echo "container CLI not found (Apple container)" >&2
  exit 1
fi

for name in child-1 child-2 worker-1 worker-2; do
  container stop "${name}" >/dev/null 2>&1 || true
  container rm "${name}" >/dev/null 2>&1 || true
done
echo "Removed child-1 and child-2 (and leftover worker-1 / worker-2, if they existed)"
