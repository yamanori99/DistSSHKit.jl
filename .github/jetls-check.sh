#!/usr/bin/env bash
# Entry files for `jetls check` (hint+). JetLS follows top-level `include()`.
#
#   ./.github/jetls-check.sh
#   ./.github/jetls-check.sh --progress=none
#   ./.github/jetls-check.sh --print-files   # CI file list
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
    test/aqua.jl
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

exec jetls --threads=auto -- check --exit-severity=hint "${jetls_args[@]}" "${files[@]}"
