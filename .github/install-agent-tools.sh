#!/usr/bin/env bash
# Idempotent Runic + JETLS install for Cloud Agent VMs (and local dev).
# Matches CI pins: Runic via Pkg.Apps, JETLS rev from jetls-check action.yml.
# Tool install failures warn only; this script exits 0 so callers' builds continue.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
JULIA_CHANNEL=1.13
JULIA_LAUNCHER="${HOME}/.juliaup/bin/julialauncher"
JETLS_ACTION="${root}/.github/actions/jetls-check/action.yml"
APP_BIN="${HOME}/.julia/bin"
# Do not export HOME, JULIA_DEPOT_PATH, or JULIA_APPS_JULIA_CMD in this shell.

warn() {
    echo "install-agent-tools: $*" >&2
}

read_jetls_rev() {
    local rev
    rev="$(grep -E -m 1 -o 'rev="[0-9]{4}-[0-9]{2}-[0-9]{2}"' "${JETLS_ACTION}" || true)"
    rev="${rev#rev=\"}"
    rev="${rev%\"}"
    if [[ ! "${rev}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        warn "JETLS date pin missing in ${JETLS_ACTION}"
        return 1
    fi
    printf '%s' "${rev}"
}

with_apps_julia() {
    # Per-invocation JULIA_APPS_JULIA_CMD only (juliaup launcher, not +channel).
    JULIA_APPS_JULIA_CMD="${JULIA_LAUNCHER}" "$@"
}

link_shim() {
    local name="$1"
    local source="${APP_BIN}/${name}"
    local dest="/usr/local/bin/${name}"
    if [[ ! -e "${source}" ]]; then
        warn "no shim at ${source}; skip link for ${name}"
        return 1
    fi
    if [[ -L "${dest}" ]] && [[ "$(readlink -f "${dest}")" == "$(readlink -f "${source}")" ]]; then
        return 0
    fi
    if [[ -e "${dest}" && ! -L "${dest}" ]]; then
        warn "refusing to replace non-symlink ${dest}"
        return 1
    fi
    if [[ -w "$(dirname "${dest}")" ]]; then
        ln -sfn "${source}" "${dest}"
        return 0
    fi
    if sudo -n ln -sfn "${source}" "${dest}" 2>/dev/null; then
        return 0
    fi
    warn "could not link ${name} into /usr/local/bin (add ${APP_BIN} to PATH)"
    return 1
}

app_runs() {
    local name="$1"
    local bin="${APP_BIN}/${name}"
    if [[ ! -x "${bin}" ]]; then
        return 1
    fi
    if [[ "${name}" == "runic" ]]; then
        with_apps_julia "${bin}" --version >/dev/null 2>&1
    else
        with_apps_julia "${bin}" version >/dev/null 2>&1
    fi
}

ensure_julia_channel() {
    if [[ ! -x "${JULIA_LAUNCHER}" ]]; then
        warn "juliaup launcher missing at ${JULIA_LAUNCHER}; run .cursor/install.sh first"
        return 1
    fi
    if ! julia +"${JULIA_CHANNEL}" --startup-file=no -e 'exit(0)' >/dev/null 2>&1; then
        warn "Julia +${JULIA_CHANNEL} is not available"
        return 1
    fi
    return 0
}

install_runic() {
    if app_runs runic; then
        echo "install-agent-tools: runic already installed"
        link_shim runic || true
        return 0
    fi
    echo "install-agent-tools: installing Runic (Pkg.Apps)"
    if ! with_apps_julia julia +"${JULIA_CHANNEL}" --startup-file=no -e '
        using Pkg
        Pkg.Apps.add("Runic")
    '; then
        warn "Runic Pkg.Apps.add failed"
        return 1
    fi
    if ! app_runs runic; then
        warn "Runic installed but runic version failed"
        return 1
    fi
    link_shim runic || true
    return 0
}

install_jetls() {
    local rev
    if ! rev="$(read_jetls_rev)"; then
        return 1
    fi
    if app_runs jetls; then
        echo "install-agent-tools: jetls already installed"
        link_shim jetls || true
        return 0
    fi
    echo "install-agent-tools: installing JETLS rev=${rev} (Pkg.Apps)"
    if ! with_apps_julia julia +"${JULIA_CHANNEL}" --startup-file=no -e "
        using Pkg
        Pkg.Apps.add(; url=\"https://github.com/aviatesk/JETLS.jl\", rev=\"${rev}\")
    "; then
        warn "JETLS Pkg.Apps.add failed"
        return 1
    fi
    if ! app_runs jetls; then
        warn "JETLS installed but jetls version failed"
        return 1
    fi
    link_shim jetls || true
    return 0
}

main() {
    mkdir -p "${APP_BIN}"
    if ! ensure_julia_channel; then
        warn "skip app installs"
        return 0
    fi
    install_runic || warn "Runic install incomplete"
    install_jetls || warn "JETLS install incomplete"
}

main "$@"