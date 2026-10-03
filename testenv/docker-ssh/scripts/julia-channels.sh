#!/usr/bin/env bash
# Source from docker-ssh / apple-container up.sh.
# Sets JULIA_DEFAULT_CHANNEL / JULIA_ALT_CHANNEL from .github/julia-slots.env
# (major.minor for juliaup). Also exports DISTSSHKIT_E2E_* for test/e2e.jl.
#
# Do not `source` the env file: values like `~1.14.0-0` would expand as ~user.

_distsshkit_julia_channel_mm() {
  # ~1.14.0-0 → 1.14 ; 1.12 → 1.12 ; 1.14-nightly → 1.14
  local raw="${1#\~}"
  if [[ "${raw}" =~ ^([0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "${raw}"
  fi
}

_distsshkit_slot_value() {
  local key="$1" file="$2" line
  line="$(grep -E "^${key}=" "${file}" | head -n1)" || return 1
  [[ -n "${line}" ]] || return 1
  printf '%s\n' "${line#*=}"
}

_distsshkit_export_julia_channels() {
  local kit_root="$1"
  local slots="${kit_root}/.github/julia-slots.env"
  local slot_stable slot_alt
  if [[ ! -f "${slots}" ]]; then
    echo "missing ${slots}" >&2
    return 1
  fi
  # First bare stable line (1.13). Nightly lines are not the E2E default.
  slot_stable="$(grep -E '^~?[0-9]+\.[0-9]' "${slots}" | grep -v nightly | head -n1 || true)"
  if [[ -z "${slot_stable}" ]]; then
    echo "no stable Julia version line in ${slots}" >&2
    return 1
  fi
  # Previous minor for setup --juliaup mismatch. Not a supported version.
  slot_alt="$(_distsshkit_slot_value JULIA_E2E_MISMATCH_CHANNEL "${slots}")" || {
    echo "JULIA_E2E_MISMATCH_CHANNEL missing in ${slots}" >&2
    return 1
  }
  export JULIA_DEFAULT_CHANNEL
  export JULIA_ALT_CHANNEL
  JULIA_DEFAULT_CHANNEL="$(_distsshkit_julia_channel_mm "${slot_stable}")"
  JULIA_ALT_CHANNEL="$(_distsshkit_julia_channel_mm "${slot_alt}")"
  export DISTSSHKIT_E2E_JULIA_DEFAULT_CHANNEL="${JULIA_DEFAULT_CHANNEL}"
  export DISTSSHKIT_E2E_JULIA_ALT_CHANNEL="${JULIA_ALT_CHANNEL}"
  echo "juliaup channels: default=${JULIA_DEFAULT_CHANNEL} alt=${JULIA_ALT_CHANNEL}"
}

# Sort key for one Julia version. Stable patch beats a prerelease of that
# same patch; callers compare stables and prereleases in separate pools.
_distsshkit_julia_ver_sort_key() {
  local ver="$1" patch kind n rank
  if [[ "${ver}" =~ ^[0-9]+\.[0-9]+\.([0-9]+)$ ]]; then
    printf '%05d\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "${ver}" =~ ^[0-9]+\.[0-9]+\.([0-9]+)-(alpha|beta|rc)([0-9]+)$ ]]; then
    patch="${BASH_REMATCH[1]}"
    kind="${BASH_REMATCH[2]}"
    n="${BASH_REMATCH[3]}"
    case "${kind}" in
      alpha) rank=0 ;;
      beta) rank=1 ;;
      rc) rank=2 ;;
    esac
    printf '%05d%d%05d\n' "${patch}" "${rank}" "${n}"
    return 0
  fi
  echo "unrecognized Julia version: ${ver}" >&2
  return 1
}

# Highest version in the argument list (`_distsshkit_julia_ver_sort_key`).
_distsshkit_julia_newest() {
  local best="" best_key="" ver key
  (($#)) || return 1
  for ver in "$@"; do
    key="$(_distsshkit_julia_ver_sort_key "${ver}")" || return 1
    # 10# forces base 10. A leading zero would make -gt read the key as octal,
    # so patch 8 or 9 (00008) is an arithmetic error and loses to 00007.
    if [[ -z "${best}" || "10#${key}" -gt "10#${best_key}" ]]; then
      best="${ver}"
      best_key="${key}"
    fi
  done
  printf '%s\n' "${best}"
}

# Newest release on one major.minor channel. versions.json object keys only
# (`  "1.13.1": {`). Stable wins over a later prerelease (1.13.1, not
# 1.13.2-rc1). With no stable yet, the newest prerelease is the channel.
_distsshkit_julia_release_for_channel() {
  local channel="$1" json="$2" esc line re_stable re_pre
  local -a stable=() pre=()
  esc="${channel//./\\.}"
  # Unquoted =~ so the escaped dots stay regex. The pattern has no spaces.
  re_stable="^[[:space:]]*\"(${esc}\\.[0-9]+)\"[[:space:]]*:"
  re_pre="^[[:space:]]*\"(${esc}\\.[0-9]+-(alpha|beta|rc)[0-9]+)\"[[:space:]]*:"
  while IFS= read -r line; do
    if [[ "${line}" =~ ${re_stable} ]]; then
      stable+=("${BASH_REMATCH[1]}")
    elif [[ "${line}" =~ ${re_pre} ]]; then
      pre+=("${BASH_REMATCH[1]}")
    fi
  done < "${json}"
  if ((${#stable[@]})); then
    _distsshkit_julia_newest "${stable[@]}"
  elif ((${#pre[@]})); then
    _distsshkit_julia_newest "${pre[@]}"
  else
    echo "no Julia release for channel ${channel}" >&2
    return 1
  fi
}

# Newest release on each channel, from versions.json. Passed as image
# build-args so the juliaup layer rebuilds when 1.13.0-rc4 becomes 1.13.1
# even though the channel name stays 1.13. Call only on the build path.
_distsshkit_export_julia_releases() {
  : "${JULIA_DEFAULT_CHANNEL:?JULIA_DEFAULT_CHANNEL unset (source julia-channels.sh first)}"
  : "${JULIA_ALT_CHANNEL:?JULIA_ALT_CHANNEL unset (source julia-channels.sh first)}"
  local json
  json="$(mktemp)"
  curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
    -fsSL -o "${json}" https://julialang-s3.julialang.org/bin/versions.json \
    || { rm -f "${json}"; echo "failed to download versions.json" >&2; return 1; }
  if ! JULIA_DEFAULT_RELEASE="$(_distsshkit_julia_release_for_channel "${JULIA_DEFAULT_CHANNEL}" "${json}")"; then
    rm -f "${json}"
    echo "failed to resolve Julia ${JULIA_DEFAULT_CHANNEL}" >&2
    return 1
  fi
  if ! JULIA_ALT_RELEASE="$(_distsshkit_julia_release_for_channel "${JULIA_ALT_CHANNEL}" "${json}")"; then
    rm -f "${json}"
    echo "failed to resolve Julia ${JULIA_ALT_CHANNEL}" >&2
    return 1
  fi
  rm -f "${json}"
  export JULIA_DEFAULT_RELEASE JULIA_ALT_RELEASE
  echo "juliaup releases: default=${JULIA_DEFAULT_CHANNEL} (${JULIA_DEFAULT_RELEASE}) alt=${JULIA_ALT_CHANNEL} (${JULIA_ALT_RELEASE})"
}
