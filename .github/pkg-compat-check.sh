#!/usr/bin/env bash
# Reject stdlib 0.0.0 unions. DistSSHKit is Julia 1.12; `< 0.0.1` is only
# for the historical Pkg.test sandbox on older Julias.
#
#   ./.github/pkg-compat-check.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if grep -n -E '<[[:space:]]*0\.0\.1\b' Project.toml test/Project.toml docs/Project.toml; then
  echo "Pkg compat: do not add < 0.0.1. Comma is a union; this package does not support Julia < 1.10." >&2
  exit 1
fi
