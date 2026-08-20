#!/usr/bin/env bash
# Entry files for `jetls check` (hint+). JetLS follows top-level `include()`.
#
#   ./.github/jetls-check.sh
#   ./.github/jetls-check.sh --progress=none
#   ./.github/jetls-check.sh --print-files   # CI file list
#
# `test/e2e.jl` is a second test entry (not included from `runtests.jl`).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
shopt -s nullglob

files=(
    src/DistSSHKit.jl
    src/cli/*.jl
    src/cli/*/*.jl
    demos/with_kit/*.jl
    demos/without_kit/*.jl
    test/runtests.jl
    test/e2e.jl
    test/fixtures/*.jl
)

if ((${#files[@]} == 0)); then
    echo "jetls-check: no entry files matched" >&2
    exit 1
fi

print_files=false
jetls_args=()
for arg in "$@"; do
    if [[ "$arg" == "--print-files" ]]; then
        print_files=true
    else
        jetls_args+=("$arg")
    fi
done

if [[ "$print_files" == true ]]; then
    printf '%s\n' "${files[*]}"
    exit 0
fi

# Pkg Apps shims pin a Julia binary. juliaup upgrades leave that path missing.
# The shim honors JULIA_APPS_JULIA_CMD; default to PATH `julia`.
if [[ -z "${JULIA_APPS_JULIA_CMD:-}" ]]; then
    export JULIA_APPS_JULIA_CMD="$(command -v julia)"
fi

exec jetls --threads=auto -- check --exit-severity=hint "${jetls_args[@]}" "${files[@]}"
