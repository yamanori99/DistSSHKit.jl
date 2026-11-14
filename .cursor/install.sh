#!/usr/bin/env bash
# Cursor cloud agent bootstrap for this repo.
# Installs juliaup if needed, Julia 1.13 (default), the 1.14 channel, and nightly,
# then instantiates and precompiles the root and test projects on 1.13.
# Re-running skips downloads that are already present.
set -euo pipefail

JULIAUP_BIN="${HOME}/.juliaup/bin/juliaup"
STABLE_CHANNEL="1.13"
# Minor channel. While 1.14 has no stable release it tracks 1.14 prereleases
# (alpha, beta, rc) and stays on 1.14 after 1.15 exists. `beta` would not.
PRERELEASE_CHANNEL="1.14"
# juliaup channel that tracks Julia master. Not the default.
NIGHTLY_CHANNEL="nightly"

if [[ ! -x "${JULIAUP_BIN}" ]]; then
  curl -fsSL https://install.julialang.org | sh -s -- \
    --yes \
    --default-channel="${STABLE_CHANNEL}" \
    --add-to-path=no \
    --background-selfupdate=0 \
    --startup-selfupdate=0
fi

if [[ ! -x "${JULIAUP_BIN}" ]]; then
  echo "juliaup install did not produce ${JULIAUP_BIN}" >&2
  exit 1
fi

# This process. Later shells resolve `julia` via /usr/local/bin (below).
export PATH="${HOME}/.juliaup/bin:${PATH}"

# Cloud Agent install/start are non-interactive login shells. Ubuntu's
# ~/.bashrc returns immediately in that case, so juliaup's PATH edit would
# not be visible. /usr/local/bin is already on the default PATH and is not
# writable by the login user, so the links need sudo.
link_into_path() {
  local name="$1"
  local source="${HOME}/.juliaup/bin/${name}"
  local dest="/usr/local/bin/${name}"
  if [[ ! -e "${source}" ]]; then
    echo "juliaup did not install ${source}" >&2
    exit 1
  fi
  if [[ -L "${dest}" ]] && [[ "$(readlink -f "${dest}")" == "$(readlink -f "${source}")" ]]; then
    return 0
  fi
  if [[ -e "${dest}" && ! -L "${dest}" ]]; then
    echo "refusing to replace non-symlink ${dest}" >&2
    exit 1
  fi
  # `julia` is a symlink to julialauncher. Linking `julia` at juliaup's
  # binary makes `julia +1.13` fail as an unknown juliaup subcommand.
  if [[ -w "$(dirname "${dest}")" ]]; then
    ln -sfn "${source}" "${dest}"
    return 0
  fi
  sudo -n ln -sfn "${source}" "${dest}"
}

link_into_path julia
link_into_path juliaup

JULIAUP_STATUS=""
refresh_status() {
  JULIAUP_STATUS="$(juliaup status)"
}

channel_present() {
  local channel="$1"
  local line fields field
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    read -r -a fields <<<"${line}"
    for field in "${fields[@]}"; do
      if [[ "${field}" == "${channel}" ]]; then
        return 0
      fi
    done
  done <<<"${JULIAUP_STATUS}"
  return 1
}

default_is() {
  local channel="$1"
  local line fields field seen
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    read -r -a fields <<<"${line}"
    seen=0
    for field in "${fields[@]}"; do
      if [[ "${field}" == "${channel}" ]]; then
        seen=1
      fi
    done
    if [[ "${seen}" -eq 1 && ( "${line}" == *"*"* || "${line}" == *"(default)"* ) ]]; then
      return 0
    fi
  done <<<"${JULIAUP_STATUS}"
  return 1
}

ensure_channel() {
  local channel="$1"
  if channel_present "${channel}"; then
    return 0
  fi
  juliaup add "${channel}"
  refresh_status
}

refresh_status
ensure_channel "${STABLE_CHANNEL}"
ensure_channel "${PRERELEASE_CHANNEL}"
ensure_channel "${NIGHTLY_CHANNEL}"
if ! default_is "${STABLE_CHANNEL}"; then
  juliaup default "${STABLE_CHANNEL}"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# One Julia process. Update the registry only when General is not already
# in the default depot, so a re-run does not hit the registry server.
# `workspace=false` limits precompile to the active project. With no
# Manifest.toml, the first instantiate still resolves the whole workspace
# (including docs) because Pkg.instantiate calls `up` in that case.
julia +"${STABLE_CHANNEL}" --startup-file=no -e '
using Pkg
root = ARGS[1]
have_reg = Ref(isdir(joinpath(first(DEPOT_PATH), "registries", "General")))
for rel in ARGS[2:end]
    proj = abspath(joinpath(root, rel))
    project = joinpath(proj, "Project.toml")
    isfile(project) || error("missing Project.toml: " * proj)
    Pkg.activate(proj)
    Pkg.instantiate(; workspace = false, update_registry = !have_reg[])
    Pkg.precompile(; workspace = false)
    have_reg[] = true
end
' -- "${repo_root}" . test

if [[ -f "${repo_root}/.github/install-agent-tools.sh" ]]; then
  bash "${repo_root}/.github/install-agent-tools.sh"
fi
