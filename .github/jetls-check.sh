#!/usr/bin/env bash
# Run `jetls check` on entry scripts only. JetLS follows `include()`, so do not
# pass src/cli/<cmd>/*.jl or src/DistSSHKit/*.jl (those are loaded by the
# entries below).
#
# Globs (new files under these dirs are picked up automatically):
#   src/DistSSHKit.jl
#   src/cli/*.jl          except _*.jl fragments
#   demos/with_kit/*.jl
#   demos/without_kit/*.jl
#   test/runtests.jl test/aqua.jl
#   test/fixtures/*.jl
#
# Extra jetls check flags: ./.github/jetls-check.sh --progress=none
#
# Usage (repo root):
#   ./.github/jetls-check.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
shopt -s nullglob

files=(src/DistSSHKit.jl test/runtests.jl test/aqua.jl)
for f in src/cli/*.jl; do
    [[ "$(basename "$f")" == _* ]] && continue
    files+=("$f")
done
files+=(demos/with_kit/*.jl demos/without_kit/*.jl test/fixtures/*.jl)

if ((${#files[@]} == 0)); then
    echo "jetls-check: no entry files matched" >&2
    exit 1
fi

exec jetls --threads=auto -- check --exit-severity=warning "$@" "${files[@]}"
