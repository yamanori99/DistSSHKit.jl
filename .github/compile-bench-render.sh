#!/usr/bin/env bash
# Rebuild the bench-data README from history already recorded. Does not measure.
#
# CI sets BENCH_PUSH=1 on main. A pull request renders the job summary and does not push.
# Token is a basic extraheader, the form actions/checkout uses. Not a clone URL.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

summary="${GITHUB_STEP_SUMMARY:-}"

render() {
    local history="$1"
    local readme="$2"
    julia --startup-file=no bench/compile/report.jl \
        --history "$history" \
        --readme "$readme"
    if [ -n "$summary" ]; then
        printf '\n' >> "$summary"
        cat "$readme" >> "$summary"
    fi
}

token="${BENCH_TOKEN:?}"
dest="${RUNNER_TEMP:?}/bench-data"
rm -rf "$dest"
url="https://github.com/${GITHUB_REPOSITORY:?}.git"
basic="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
echo "::add-mask::${basic}"
auth=(-c "http.extraheader=AUTHORIZATION: basic ${basic}")
# Exit 2 is "no matching ref". Any other failure is auth or the network.
rc=0
git "${auth[@]}" ls-remote --exit-code --heads "$url" bench-data >/dev/null || rc=$?
if [ "$rc" = "2" ]; then
    echo "no bench-data branch; nothing to render"
    exit 0
elif [ "$rc" != "0" ]; then
    exit "$rc"
fi
git "${auth[@]}" clone --branch bench-data --single-branch "$url" "$dest"
found="$(find "$dest/history" -name '*.toml' -print -quit || true)"
if [ -z "$found" ]; then
    echo "bench-data has no history; nothing to render"
    exit 0
fi
render "$dest/history" "$dest/README.md"

if [ "${BENCH_PUSH:-0}" != "1" ] || [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] || [ "${GITHUB_REF:-}" != "refs/heads/main" ]; then
    echo "rendered; bench-data was not pushed"
    exit 0
fi

git -C "$dest" config http.extraheader "AUTHORIZATION: basic ${basic}"
git -C "$dest" add README.md
if git -C "$dest" diff --cached --quiet; then
    echo "README unchanged"
    exit 0
fi
git -C "$dest" \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "Render compile bench."
for _ in 1 2 3; do
    git -C "$dest" push origin HEAD:bench-data && exit 0
    git -C "$dest" pull --rebase origin bench-data
done
exit 1
