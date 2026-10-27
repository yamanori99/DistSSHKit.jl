#!/usr/bin/env bash
# Rebuild the bench-data README from history already recorded. Does not measure.
#
# CI sets BENCH_PUSH=1 on main. A pull request renders the job summary and does not push.
# A main run also copies bench.html to the root of gh-pages. GitHub Pages serves that
# file as HTML. jsDelivr serves HTML as text/plain, so the public link is Pages.
# The publish jobs share the docs-gh-pages queue with Deploy docs.
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
net=(-c http.connectTimeout=10 -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30)
# Exit 2 is "no matching ref". Any other failure is auth or the network.
rc=0
git "${net[@]}" "${auth[@]}" ls-remote --exit-code --heads "$url" bench-data >/dev/null || rc=$?
if [ "$rc" = "2" ]; then
    echo "no bench-data branch; nothing to render"
    exit 0
elif [ "$rc" != "0" ]; then
    exit "$rc"
fi
git "${net[@]}" "${auth[@]}" clone --branch bench-data --single-branch "$url" "$dest"
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

# Repo identity. `-c` on `commit` does not apply to `pull --rebase`.
git_bot() {
    git -C "$1" config user.name "github-actions[bot]"
    git -C "$1" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
}

commit_as_bot() {
    git_bot "$1"
    git -C "$1" commit -m "$2"
}

# Six tries. 1.13, 1.14-pre, and nightly can push the same branch together.
# A rejected push rebases onto the new tip and tries again.
push_ref() {
    local dir="$1"
    local branch="$2"
    local attempt
    for attempt in 1 2 3 4 5 6; do
        if git "${net[@]}" -C "$dir" push origin "HEAD:${branch}"; then
            return 0
        fi
        if ! git "${net[@]}" -C "$dir" pull --rebase origin "$branch"; then
            echo "rebase onto ${branch} failed (attempt ${attempt})" >&2
            git -C "$dir" rebase --abort || true
            return 1
        fi
        if [ "$attempt" -lt 6 ]; then
            sleep "$attempt"
        fi
    done
    git "${net[@]}" -C "$dir" push origin "HEAD:${branch}"
}

git -C "$dest" config http.extraheader "AUTHORIZATION: basic ${basic}"
git -C "$dest" add README.md bench.html
if git -C "$dest" diff --cached --quiet; then
    echo "bench-data unchanged"
else
    commit_as_bot "$dest" "Render compile bench."
    push_ref "$dest" bench-data
fi

# gh-pages holds every docs version. A full checkout is about 1.5 GB.
# A sparse partial clone checks out bench.html only.
pages="${RUNNER_TEMP:?}/gh-pages"
rm -rf "$pages"
git "${net[@]}" "${auth[@]}" clone \
    --filter=blob:none --sparse --depth 1 \
    --branch gh-pages --single-branch \
    "$url" "$pages"
# Cone mode refuses a file path. bench.html is a file at the root.
git -C "$pages" sparse-checkout set --skip-checks bench.html
cp "$dest/bench.html" "$pages/bench.html"
git -C "$pages" config http.extraheader "AUTHORIZATION: basic ${basic}"
git -C "$pages" add bench.html
if git -C "$pages" diff --cached --quiet; then
    echo "gh-pages bench.html unchanged"
    exit 0
fi
commit_as_bot "$pages" "Publish compile bench page."
# pull --rebase on this shallow clone would fetch the rest of the docs tree.
# Rebase rewrites the commit, so this repo needs the same identity as bench-data.
push_pages() {
    local attempt
    for attempt in 1 2 3 4 5 6; do
        if git "${net[@]}" -C "$pages" push origin HEAD:gh-pages; then
            return 0
        fi
        if ! git "${net[@]}" -C "$pages" fetch --filter=blob:none --depth=1 origin gh-pages; then
            echo "fetch gh-pages failed (attempt ${attempt})" >&2
            return 1
        fi
        if ! git -C "$pages" rebase --onto FETCH_HEAD HEAD~1; then
            echo "rebase onto gh-pages failed (attempt ${attempt})" >&2
            git -C "$pages" rebase --abort || true
            return 1
        fi
        if [ "$attempt" -lt 6 ]; then
            sleep "$attempt"
        fi
    done
    git "${net[@]}" -C "$pages" push origin HEAD:gh-pages
}
push_pages
