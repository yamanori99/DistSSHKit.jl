#!/usr/bin/env bash
# Print true when Project.toml version at NEW is greater than at OLD.
# Usage: ./.github/version-cut.sh OLD NEW
set -euo pipefail

old_ref="${1:?old ref}"
new_ref="${2:?new ref}"

ensure() {
  local ref="$1"
  git cat-file -e "${ref}^{commit}" 2>/dev/null && return 0
  if ! git fetch --depth=1 origin "$ref"; then
    if [ -n "${PR:-}" ]; then
      git fetch --depth=1 origin "refs/pull/${PR}/head"
    fi
  fi
  git cat-file -e "${ref}^{commit}"
}

ensure "$old_ref"
ensure "$new_ref"

ver() {
  git cat-file -p "${1}:Project.toml" \
    | sed -n 's/^version[[:space:]]*=[[:space:]]*"\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2 \3/p' \
    | head -1
}

read -r om oi op <<<"$(ver "$old_ref")" || true
read -r nm ni np <<<"$(ver "$new_ref")" || true
if [ -n "${om:-}" ] && [ -n "${nm:-}" ]; then
  if [ "$nm" -gt "$om" ] || { [ "$nm" -eq "$om" ] && [ "$ni" -gt "$oi" ]; } || { [ "$nm" -eq "$om" ] && [ "$ni" -eq "$oi" ] && [ "$np" -gt "$op" ]; }; then
    echo true
    exit 0
  fi
fi
echo false
