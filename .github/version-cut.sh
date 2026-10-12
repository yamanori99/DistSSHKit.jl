#!/usr/bin/env bash
# Print true when Project.toml version at NEW is a release cut from OLD.
# A prerelease (a hyphen, as in 0.2.0-DEV) is not a cut.
# The same numbers with the prerelease removed (0.2.0-DEV -> 0.2.0) is a cut.
# Usage: ./.github/version-cut.sh OLD NEW
#        ./.github/version-cut.sh --self-test
set -euo pipefail

split_ver() {
  printf '%s\n' "$1" | sed -n \
    's/^\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(-[^ ]*\)\{0,1\}$/\1 \2 \3 \4/p'
}

# echo true or false
is_cut() {
  local old="$1" new="$2"
  local om oi op opre nm ni np npre
  read -r om oi op opre <<<"$(split_ver "$old")" || true
  read -r nm ni np npre <<<"$(split_ver "$new")" || true
  if [ -z "${om:-}" ] || [ -z "${nm:-}" ]; then
    echo false
    return 0
  fi
  if [ -n "${npre:-}" ]; then
    echo false
    return 0
  fi
  if [ "$nm" -gt "$om" ] || { [ "$nm" -eq "$om" ] && [ "$ni" -gt "$oi" ]; } \
    || { [ "$nm" -eq "$om" ] && [ "$ni" -eq "$oi" ] && [ "$np" -gt "$op" ]; }; then
    echo true
    return 0
  fi
  if [ "$nm" -eq "$om" ] && [ "$ni" -eq "$oi" ] && [ "$np" -eq "$op" ] && [ -n "${opre:-}" ]; then
    echo true
    return 0
  fi
  echo false
}

self_test() {
  local failed=0
  expect() {
    local got
    got="$(is_cut "$1" "$2")"
    if [ "$got" != "$3" ]; then
      echo "FAIL $1 -> $2 want $3 got $got" >&2
      failed=1
    fi
  }
  expect 0.1.5 0.1.6 true
  expect 0.1.6 0.2.0 true
  expect 0.1.6 0.2.0-DEV false
  expect 0.2.0-DEV 0.2.0 true
  expect 0.2.0-DEV 0.2.0-DEV false
  expect 0.1.6 0.1.6 false
  expect 0.2.0 0.1.9 false
  expect 0.2.0-DEV 0.2.1 true
  expect 0.2.0-alpha 0.2.0-beta false
  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
  echo "version-cut self-test ok"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

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

ver_string() {
  git cat-file -p "${1}:Project.toml" \
    | sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1
}

ensure "$old_ref"
ensure "$new_ref"
is_cut "$(ver_string "$old_ref")" "$(ver_string "$new_ref")"
