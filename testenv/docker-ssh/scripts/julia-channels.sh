#!/usr/bin/env bash
# Source from docker-ssh / apple-container up.sh.
# Sets JULIA_DEFAULT_CHANNEL / JULIA_ALT_CHANNEL from .github/julia-slots.env
# (major.minor for juliaup). Also exports DISTSSHKIT_E2E_* for test/e2e.jl.
#
# Do not `source` the env file: values like `~1.13.0-0` would expand as ~user.

_distsshkit_julia_channel_mm() {
  # ~1.13.0-0 → 1.13 ; 1.12 → 1.12 ; 1.14-nightly → 1.14
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
  local slot_min slot_max
  if [[ ! -f "${slots}" ]]; then
    echo "missing ${slots}" >&2
    return 1
  fi
  slot_min="$(_distsshkit_slot_value JULIA_SLOT_MIN "${slots}")" || {
    echo "JULIA_SLOT_MIN missing in ${slots}" >&2
    return 1
  }
  slot_max="$(_distsshkit_slot_value JULIA_SLOT_MAX "${slots}")" || {
    echo "JULIA_SLOT_MAX missing in ${slots}" >&2
    return 1
  }
  export JULIA_DEFAULT_CHANNEL
  export JULIA_ALT_CHANNEL
  JULIA_DEFAULT_CHANNEL="$(_distsshkit_julia_channel_mm "${slot_max}")"
  JULIA_ALT_CHANNEL="$(_distsshkit_julia_channel_mm "${slot_min}")"
  export DISTSSHKIT_E2E_JULIA_DEFAULT_CHANNEL="${JULIA_DEFAULT_CHANNEL}"
  export DISTSSHKIT_E2E_JULIA_ALT_CHANNEL="${JULIA_ALT_CHANNEL}"
  echo "juliaup channels: default=${JULIA_DEFAULT_CHANNEL} alt=${JULIA_ALT_CHANNEL}"
}
