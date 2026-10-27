#!/usr/bin/env bash
# Julia inside WSL2. The caller is wsl-bash and cwd is the Actions checkout.
# The workflow's actions/cache restores .ci-cache/wsl-julia (one channel per key).
#
#   ./.github/wsl-julia.sh <juliaup-channel-or-setup-julia-range> <command...>
#
# `1.13` and `nightly` are juliaup channels. A tilde range such as `~1.14.0-0`
# is the setup-julia version string: the highest match in versions.json, the
# same file julia-actions/setup-julia reads. juliaup has no range channels, and
# its `1.14` channel can lag that file, so the range path downloads the linux
# x64 archive itself.
set -euo pipefail

# Ubuntu-24.04's WSL rootfs usually has these. Install only when it does not,
# so Vampire/setup-wsl does not apt-get on every job.
ensure_cmds() {
  local missing=()
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "WSL image is missing ${missing[*]}; need root to install" >&2
    return 1
  fi
  export DEBIAN_FRONTEND=noninteractive
  timeout 180 apt-get update -qq
  timeout 180 apt-get install -y --no-install-recommends ca-certificates "${missing[@]}"
}

# Highest version in versions.json that node-semver accepts for a tilde range
# with includePrerelease false. `~1.14.0-0` is >=1.14.0-0 and <1.15.0-0.
# A prerelease matches only when one of those bounds carries a prerelease on
# the same major.minor.patch, so 1.14.1-rc1 does not match and 1.15 does not.
resolve_tilde() {
  local spec="$1" versions_json="$2"
  python3 - "$spec" "$versions_json" <<'PY'
import json, re, sys

spec = sys.argv[1]
path = sys.argv[2]
match = re.fullmatch(r"~(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?", spec)
if not match:
    sys.exit(f"not a tilde range: {spec}")
major, minor, patch = (int(match.group(i)) for i in (1, 2, 3))
lower_pre = match.group(4)
upper = (major, minor + 1, 0, "0")
lower = (major, minor, patch, lower_pre)
pre_tuples = {(major, minor, patch), (major, minor + 1, 0)}

def pre_key(text):
    if text is None:
        return None
    parts = []
    for part in text.split("."):
        if part.isdigit():
            parts.append((0, int(part)))
        else:
            parts.append((1, part))
    return tuple(parts)

def cmp_ver(a, b):
    if a[:3] != b[:3]:
        return (a[:3] > b[:3]) - (a[:3] < b[:3])
    ap, bp = pre_key(a[3]), pre_key(b[3])
    if ap is None and bp is None:
        return 0
    if ap is None:
        return 1
    if bp is None:
        return -1
    n = min(len(ap), len(bp))
    for i in range(n):
        if ap[i] != bp[i]:
            return (ap[i] > bp[i]) - (ap[i] < bp[i])
    return (len(ap) > len(bp)) - (len(ap) < len(bp))

def satisfies(ver):
    if cmp_ver(ver, lower) < 0 or cmp_ver(ver, upper) >= 0:
        return False
    if ver[3] is not None and ver[:3] not in pre_tuples:
        return False
    return True

version_re = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")
with open(path, encoding="utf-8") as fh:
    info = json.load(fh)
best = None
for key in info:
    parsed = version_re.fullmatch(key)
    if not parsed:
        continue
    ver = (int(parsed.group(1)), int(parsed.group(2)), int(parsed.group(3)), parsed.group(4))
    if not satisfies(ver):
        continue
    if best is None or cmp_ver(ver, best[0]) > 0:
        best = (ver, key)
if best is None:
    sys.exit(f"no Julia version matches {spec}")
chosen = best[1]
archive = None
for item in info[chosen].get("files", []):
    if (
        item.get("os") == "linux"
        and item.get("arch") == "x86_64"
        and item.get("kind") == "archive"
        and str(item.get("url", "")).endswith(".tar.gz")
    ):
        archive = item
        break
if archive is None:
    sys.exit(f"no linux x64 archive for {chosen}")
sys.stdout.write(f"{chosen}\t{archive['url']}\t{archive['sha256']}\n")
PY
}

install_tilde() {
  local spec="$1"
  local versions_json resolved version url sha archive current
  versions_json="$(mktemp)"
  curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
    -fsSL -o "$versions_json" https://julialang-s3.julialang.org/bin/versions.json
  resolved="$(resolve_tilde "$spec" "$versions_json")"
  rm -f "$versions_json"
  version="${resolved%%$'\t'*}"
  url="${resolved#*$'\t'}"
  url="${url%%$'\t'*}"
  sha="${resolved##*$'\t'}"
  echo "Julia ${spec} resolved to ${version}"
  current=""
  if [[ -x "$HOME/.julia-dist/julia/bin/julia" ]]; then
    current="$("$HOME/.julia-dist/julia/bin/julia" --version 2>/dev/null || true)"
  fi
  if [[ "$current" == "julia version ${version}" ]]; then
    echo "kept cached Julia ${version}"
    return 0
  fi
  rm -rf "$HOME/.julia" "$HOME/.julia-dist"
  archive="$(mktemp)"
  curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
    -fsSL -o "$archive" "$url"
  echo "${sha}  ${archive}" | sha256sum -c -
  mkdir -p "$HOME/.julia-dist/julia"
  tar -xzf "$archive" -C "$HOME/.julia-dist/julia" --strip-components=1
  rm -f "$archive"
  "$HOME/.julia-dist/julia/bin/julia" --version
}

channel="$1"
shift
ensure_cmds curl git

src="$(pwd)"
dest="$HOME/DistSSHKit.jl"
cache="$src/.ci-cache/wsl-julia"
mkdir -p "$cache"
rm -rf "$dest"
git clone "$src" "$dest"
# juliaup does not retry its own download of a nightly tarball. The curl
# retries cover only https://install.julialang.org.
install_julia() {
  local attempt
  for attempt in 1 2 3; do
    rm -rf "$HOME/.juliaup" "$HOME/.julia"
    if curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
      -fsSL https://install.julialang.org | sh -s -- --yes --default-channel "$channel"
    then
      return 0
    fi
    echo "Julia install attempt ${attempt} failed" >&2
    sleep $((attempt * 10))
  done
  echo "Julia install failed after 3 attempts" >&2
  return 1
}
restored=0
if [[ -f "$cache/julia.tgz" ]]; then
  tar -xzf "$cache/julia.tgz" -C "$HOME"
  restored=1
fi
if [[ "$channel" == "~"* ]]; then
  ensure_cmds python3
  # Re-resolve on a cache hit so alpha -> beta -> rc -> 1.14.0 replaces the
  # cached build. A matching julia version keeps the depot.
  install_tilde "$channel"
  export PATH="$HOME/.julia-dist/julia/bin:$PATH"
else
  if [[ "$restored" -eq 0 ]]; then
    install_julia
  fi
  export PATH="$HOME/.juliaup/bin:$PATH"
  # A cache hit would keep the first nightly build. Move that channel forward.
  if [[ "$restored" -eq 1 && ( "$channel" == "nightly" || "$channel" == *-nightly ) ]]; then
    juliaup update "$channel"
  fi
fi
cd "$dest"
"$@"
if [[ "$channel" == "~"* ]]; then
  cache_parts=(.julia-dist)
  if [[ -d "$HOME/.julia" ]]; then
    cache_parts+=(.julia)
  fi
  tar -czf "$cache/julia.tgz" -C "$HOME" "${cache_parts[@]}"
elif [[ -d "$HOME/.julia" ]]; then
  tar -czf "$cache/julia.tgz" -C "$HOME" .juliaup .julia
else
  tar -czf "$cache/julia.tgz" -C "$HOME" .juliaup
fi
