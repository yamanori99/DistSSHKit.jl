#!/usr/bin/env bash
# Colima on macOS Intel GitHub runners (SSH E2E after merge).
# Apple Silicon GitHub runners lack nested virt — this script requires x86_64.
# Replaces douglascamata/setup-docker-macos-action with curl retries so Lima
# downloads do not pipe a truncated tarball into tar.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "setup-colima-ci.sh is for macOS runners only" >&2
  exit 1
fi

arch="$(uname -m)"
if [[ "$arch" == "arm64" ]]; then
  echo "Apple Silicon runners lack nested virtualization; use macos-*-intel" >&2
  exit 1
fi

# Pin for reproducible CI (bump intentionally).
LIMA_VERSION="${LIMA_VERSION:-v2.1.4}"
COLIMA_VERSION="${COLIMA_VERSION:-v0.10.3}"

retry() {
  local attempt=1
  local max=5
  local delay=10
  until "$@"; do
    if (( attempt >= max )); then
      echo "command failed after ${max} attempts: $*" >&2
      return 1
    fi
    echo "retry ${attempt}/${max} in ${delay}s: $*" >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

download() {
  local url="$1"
  local out="$2"
  retry curl -fL --connect-timeout 30 --retry 5 --retry-all-errors --retry-delay 5 \
    -o "$out" "$url"
  # Reject empty / HTML error pages before extract.
  [[ -s "$out" ]] || {
    echo "download empty: $url" >&2
    return 1
  }
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "::group::Install Lima ${LIMA_VERSION}"
# Lima v2+ ships helpers under libexec.
if [[ "$LIMA_VERSION" == v2.* ]]; then
  sudo mkdir -p /usr/local/libexec
  sudo chown "$(id -u):$(id -g)" /usr/local/libexec
fi
lima_tgz="$tmpdir/lima.tgz"
download \
  "https://github.com/lima-vm/lima/releases/download/${LIMA_VERSION}/lima-${LIMA_VERSION#v}-$(uname -s)-${arch}.tar.gz" \
  "$lima_tgz"
tar -tzf "$lima_tgz" >/dev/null
sudo tar -C /usr/local -xzf "$lima_tgz"
echo "::endgroup::"

echo "::group::Install Colima ${COLIMA_VERSION}"
colima_bin="$tmpdir/colima"
download \
  "https://github.com/abiosoft/colima/releases/download/${COLIMA_VERSION}/colima-$(uname)-${arch}" \
  "$colima_bin"
chmod +x "$colima_bin"
sudo install "$colima_bin" /usr/local/bin/colima
echo "::endgroup::"

echo "::group::Install Docker CLI (Homebrew)"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_UPGRADE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_ENV_HINTS=1
# Runner brew prints GitHub workflow warnings (env hints, aws/tap trust). Not kit issues.
retry env -u GITHUB_ACTIONS brew install docker docker-compose docker-buildx
mkdir -p "${HOME}/.docker/cli-plugins"
ln -sfn "$(brew --prefix docker-compose)/bin/docker-compose" "${HOME}/.docker/cli-plugins/docker-compose"
ln -sfn "$(brew --prefix docker-buildx)/bin/docker-buildx" "${HOME}/.docker/cli-plugins/docker-buildx"
echo "::endgroup::"

cpu_count="$(sysctl -n hw.ncpu)"
memory_gb="$(sysctl hw.memsize | awk '{print int($2/1024/1024/1024)}')"
# localhost port publish is enough for our compose stack (macOS 15 LNP).
colima_args=(--cpu "$cpu_count" --memory "$memory_gb" --arch x86_64 --vm-type=vz --mount-type=virtiofs)

echo "::group::Start Colima ${colima_args[*]}"
colima start "${colima_args[@]}"
echo "::endgroup::"

docker version
docker compose version
colima version
