#!/usr/bin/env bash
# Entry files for `jetls check` (hint+). JetLS follows top-level `include()`.
#
#   ./.github/jetls-check.sh
#   ./.github/jetls-check.sh --progress=none
#   ./.github/jetls-check.sh --print-files   # CI file list
#
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
shopt -s nullglob

files=(
    src/DistSSHKit.jl
    test/runtests.jl
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

# Match aviatesk/JETLS.jl check@release and CI: do not pass `--threads=auto`.
# That segfaults on Julia 1.13 in signature_analysis_worker (exit 139).
# --exit-severity=hint already fails the job. --show-severity=hint prints that text;
# the CLI hides hint diagnostics otherwise.
exec jetls check --root=. --exit-severity=hint --show-severity=hint "${jetls_args[@]}" "${files[@]}"
