#!/usr/bin/env bash
# Ensure the kit parent has juliaup + default/alt channels for
# `setup --juliaup parent` SSH E2E. CI uses julia-actions/setup-julia
# (no juliaup); remotes already bake both channels in the worker image.
#
# Expects JULIA_DEFAULT_CHANNEL / JULIA_ALT_CHANNEL (from julia-channels.sh).
# Does not change PATH `julia` used to run the suite.
set -euo pipefail

: "${JULIA_DEFAULT_CHANNEL:?JULIA_DEFAULT_CHANNEL unset (source julia-channels.sh first)}"
: "${JULIA_ALT_CHANNEL:?JULIA_ALT_CHANNEL unset (source julia-channels.sh first)}"

JU="${HOME}/.juliaup/bin/juliaup"

if [[ ! -x "${JU}" ]]; then
  echo "kit parent: installing juliaup (default channel ${JULIA_DEFAULT_CHANNEL})..."
  curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
    -fsSL https://install.julialang.org |
    sh -s -- --yes --default-channel "${JULIA_DEFAULT_CHANNEL}"
fi

if [[ ! -x "${JU}" ]]; then
  echo "juliaup missing after install: ${JU}" >&2
  exit 1
fi

# Both channels must exist so E2E can mismatch then realign.
"${JU}" add "${JULIA_DEFAULT_CHANNEL}" >/dev/null || true
"${JU}" add "${JULIA_ALT_CHANNEL}" >/dev/null || true

echo "kit parent juliaup: $("${JU}" --version 2>/dev/null || echo ok) (channels ${JULIA_DEFAULT_CHANNEL} / ${JULIA_ALT_CHANNEL})"
