#!/usr/bin/env bash
# Render a README from history. Does not measure or push.
#
#   ./bench/compile/render.sh --history /path/to/bench-data/history
#   ./bench/compile/render.sh --history /path/history --readme /path/README.md
#
# Without --readme, the README is written next to the history directory.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

history=""
readme=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --history)
            history="$2"
            shift 2
            ;;
        --readme)
            readme="$2"
            shift 2
            ;;
        *)
            echo "unknown arg: $1" >&2
            exit 2
            ;;
    esac
done

if [ -z "$history" ]; then
    echo "missing --history" >&2
    exit 2
fi
if [ -z "$readme" ]; then
    readme="$(cd "$(dirname "$history")" && pwd)/README.md"
fi

julia --startup-file=no bench/compile/report.jl --history "$history" --readme "$readme"
echo "wrote $readme"
echo "wrote $(cd "$(dirname "$readme")" && pwd)/bench.html"
