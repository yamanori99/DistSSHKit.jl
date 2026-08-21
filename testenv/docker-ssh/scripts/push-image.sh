#!/usr/bin/env bash
# Tag LOCAL_IMAGE (default local/linux-ssh-worker:latest) and push with retries.
# GHCR often fails a single push with "unknown blob" after layers uploaded.
set -euo pipefail

image="${1:?usage: $0 <registry/image:tag>}"
local_image="${DISTSSHKIT_LOCAL_IMAGE:-local/linux-ssh-worker:latest}"
retries="${DISTSSHKIT_WORKER_PUSH_RETRIES:-8}"

remote_ok() {
  if docker buildx imagetools inspect "$image" >/dev/null 2>&1; then
    return 0
  fi
  docker manifest inspect "$image" >/dev/null 2>&1
}

docker tag "$local_image" "$image"
attempt=1
while true; do
  if docker push "$image" && remote_ok; then
    echo "pushed and visible: ${image}"
    exit 0
  fi
  if (( attempt >= retries )); then
    echo "docker push failed after ${retries} attempts: ${image}" >&2
    exit 1
  fi
  echo "retrying docker push (${attempt}/${retries}): ${image}" >&2
  sleep $((attempt * 8))
  attempt=$((attempt + 1))
done
