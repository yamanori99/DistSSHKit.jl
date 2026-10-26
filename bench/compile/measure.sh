#!/usr/bin/env bash
# Measure this checkout. Does not push.
#
#   ./bench/compile/measure.sh
#   ./bench/compile/measure.sh --slot 1.13 --out /tmp/compile-bench.toml
#   ./bench/compile/measure.sh --history /path/to/bench-data/history
#
# --history copies the toml to history/<slot>/<UTC date>-<shortsha>.toml
# and does not commit. Render that directory with bench/compile/render.sh.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

slot="local"
out=""
history=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --slot)
            slot="$2"
            shift 2
            ;;
        --out)
            out="$2"
            shift 2
            ;;
        --history)
            history="$2"
            shift 2
            ;;
        *)
            echo "unknown arg: $1" >&2
            exit 2
            ;;
    esac
done

if [ -z "$out" ]; then
    # macOS mktemp requires the X characters at the end of the template.
    stage="$(mktemp -d "${TMPDIR:-/tmp}/compile-bench.XXXXXX")"
    out="$stage/compile-bench.toml"
fi

julia --startup-file=no --project=. bench/compile/measure.jl --out "$out" --slot "$slot"
echo "wrote $out"

if [ -n "$history" ]; then
    sha="$(git rev-parse --short=7 HEAD 2>/dev/null || echo local)"
    day="$(date -u +%Y-%m-%d)"
    dest="$history/$slot/${day}-${sha}.toml"
    mkdir -p "$(dirname "$dest")"
    cp "$out" "$dest"
    echo "copied $dest"
fi
