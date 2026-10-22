#!/usr/bin/env bash
# Open or update ci/jetls-pin when JETLS release has a newer date tag.
#
#   ./.github/jetls-pin.sh                 # dry-run
#   JETLS_PIN_APPLY=1 ./.github/jetls-pin.sh
#
# A missing date pin, or a release commit with no YYYY-MM-DD tag, exits 0.
# The date in rev="YYYY-MM-DD" is the only text this rewrites.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

action=".github/actions/jetls-check/action.yml"
jetls_url="https://github.com/aviatesk/JETLS.jl.git"
branch="ci/jetls-pin"
apply="${JETLS_PIN_APPLY:-}"

pin="$(grep -E -o 'rev="[0-9]{4}-[0-9]{2}-[0-9]{2}"' "$action" | head -n 1 || true)"
pin="${pin#rev=\"}"
pin="${pin%\"}"
if [[ ! "$pin" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "jetls-pin: no date pin in $action"
    exit 0
fi

remote="$(git ls-remote "$jetls_url" refs/heads/release 'refs/tags/*')"
release_sha="$(printf '%s\n' "$remote" | awk '$2 == "refs/heads/release" { print $1; exit }')"
if [[ -z "$release_sha" ]]; then
    echo "jetls-pin: JETLS release ref is missing" >&2
    exit 1
fi

best="$(
    printf '%s\n' "$remote" | awk -v rel="$release_sha" '
        $2 ~ /^refs\/tags\/[0-9]{4}-[0-9]{2}-[0-9]{2}(\^\{\})?$/ {
            tag = $2
            sub(/^refs\/tags\//, "", tag)
            peeled = (tag ~ /\^\{\}$/)
            sub(/\^\{\}$/, "", tag)
            if (!(tag in sha) || peeled) {
                sha[tag] = $1
            }
        }
        END {
            best = ""
            for (t in sha) {
                if (sha[t] == rel && (best == "" || t > best)) {
                    best = t
                }
            }
            print best
        }
    '
)"

if [[ -z "$best" ]]; then
    echo "jetls-pin: release ${release_sha:0:12} has no date tag; pin stays $pin"
    exit 0
fi

if [[ "$best" == "$pin" || "$best" < "$pin" ]]; then
    echo "jetls-pin: pin $pin is current for release tag $best"
    exit 0
fi

echo "jetls-pin: release tag $best is newer than pin $pin"
if [[ "$apply" != "1" ]]; then
    echo "jetls-pin: dry-run, set JETLS_PIN_APPLY=1 to open the pull request"
    exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "jetls-pin: worktree is dirty" >&2
    exit 1
fi

git fetch origin main
git checkout -B "$branch" origin/main
python3 - "$action" "$pin" "$best" <<'PY'
import pathlib
import sys

path, old, new = sys.argv[1:]
file = pathlib.Path(path)
file.write_text(file.read_text().replace(f'rev="{old}"', f'rev="{new}"', 1))
PY

if git diff --quiet -- "$action"; then
    echo "jetls-pin: main already pins $best"
    exit 0
fi

git add "$action"
git commit -m "$(cat <<EOF
ci: pin JETLS to the ${best} release

The date tag on JETLS release moved past the pin.

EOF
)"

remote_sha="$(git ls-remote origin "refs/heads/${branch}" | awk '{ print $1; exit }')"
if [[ -n "$remote_sha" ]]; then
    git push --force-with-lease="refs/heads/${branch}:${remote_sha}" origin "HEAD:${branch}"
else
    git push -u origin "HEAD:${branch}"
fi

title="ci: pin JETLS to the ${best} release"
body="$(cat <<EOF
## Summary

- CI installs JETLS \`${best}\` instead of \`${pin}\`.
- That date tag points at the current \`release\` commit. A failed check on this pull request leaves main on \`${pin}\`.

## Testing

- This pull request changes the date in \`.github/actions/jetls-check/action.yml\`. The JETLS job on this pull request installs that rev.

## Risk

Merging this pull request makes later checks use JETLS ${best}. Leaving it open keeps main on ${pin}.

## Revert

After this merges, revert the squash commit.

## Checklist

- [x] Breaking status is correct
- [x] Version is correct — \`Project.toml\` \`version\` stayed
- [x] Remote / smoke is done, or this change does not need it
EOF
)"

existing="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')"
if [[ -n "$existing" ]]; then
    gh pr edit "$existing" --title "$title" --body "$body"
    echo "jetls-pin: updated #${existing}"
else
    gh pr create --title "$title" --body "$body"
fi
