#!/usr/bin/env bash
# On a version cut, the NEWS section for the new version must match the bump.
# Below 1.0, a higher minor needs a ### Breaking heading. A patch must not
# have one. Dropping -DEV from X.Y.0 is a breaking cut; dropping it from a
# patch prerelease is a patch cut. A higher major needs ### Breaking too.
# Versions at or above 1.0 fail until those rules exist.
# Usage: ./.github/release-news.sh OLD_REF NEW_REF
#        ./.github/release-news.sh --self-test
set -euo pipefail

split_ver() {
  printf '%s\n' "$1" | sed -n \
    's/^\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\)\(-[^ ]*\)\{0,1\}$/\1 \2 \3 \4/p'
}

# echo: breaking, patch, or unknown
classify() {
  local old="$1" new="$2"
  local om oi op opre nm ni np npre
  read -r om oi op opre <<<"$(split_ver "$old")" || true
  read -r nm ni np npre <<<"$(split_ver "$new")" || true
  if [ -z "${om:-}" ] || [ -z "${nm:-}" ]; then
    echo unknown
    return 0
  fi
  if [ "$nm" -gt "$om" ]; then
    echo breaking
    return 0
  fi
  if [ "$om" -eq 0 ] && [ "$nm" -eq 0 ]; then
    if [ "$ni" -gt "$oi" ]; then
      echo breaking
      return 0
    fi
    if [ "$ni" -eq "$oi" ] && [ "$np" -gt "$op" ]; then
      echo patch
      return 0
    fi
    if [ "$ni" -eq "$oi" ] && [ "$np" -eq "$op" ] && [ -n "${opre:-}" ] && [ -z "${npre:-}" ]; then
      if [ "$np" -eq 0 ]; then
        echo breaking
      else
        echo patch
      fi
      return 0
    fi
  fi
  echo unknown
}

section_has_breaking() {
  local version="$1" file="$2"
  awk -v ver="$version" '
    function is_heading(line, version,    hdr, rest) {
      hdr = "## " version
      if (line == hdr) return 1
      if (index(line, hdr) != 1) return 0
      rest = substr(line, length(hdr) + 1)
      return rest ~ /^[ \t]*$/
    }
    BEGIN { found = 0 }
    is_heading($0, ver) { found = 1; next }
    found && $0 ~ /^## / { exit }
    found && $0 ~ /^### Breaking[ \t]*$/ { hit = 1; exit }
    END { exit !hit }
  ' "$file"
}

section_exists() {
  local version="$1" file="$2"
  awk -v ver="$version" '
    function is_heading(line, version,    hdr, rest) {
      hdr = "## " version
      if (line == hdr) return 1
      if (index(line, hdr) != 1) return 0
      rest = substr(line, length(hdr) + 1)
      return rest ~ /^[ \t]*$/
    }
    is_heading($0, ver) { found = 1; exit }
    END { exit !found }
  ' "$file"
}

# return 0 when NEWS matches the bump
check_news() {
  local old="$1" new="$2" file="$3"
  local kind
  kind="$(classify "$old" "$new")"
  if [ "$kind" = unknown ]; then
    echo "Version rules for ${old} -> ${new} are not decided. See docs/src/developers/releasing.md." >&2
    return 1
  fi
  if ! section_exists "$new" "$file"; then
    echo "NEWS.md has no section ## ${new}." >&2
    return 1
  fi
  local has=false
  if section_has_breaking "$new" "$file"; then
    has=true
  fi
  if [ "$kind" = patch ] && [ "$has" = true ]; then
    echo "Patch ${new} has a ### Breaking section. Raise the minor, or move those items out of this section." >&2
    return 1
  fi
  if [ "$kind" = breaking ] && [ "$has" = false ]; then
    echo "Breaking bump ${new} has no ### Breaking section." >&2
    return 1
  fi
  echo "NEWS section ## ${new} matches a ${kind} bump."
}

self_test() {
  local tmp failed=0
  tmp="$(mktemp -d)"
  write_news() {
    cat >"${tmp}/NEWS.md"
  }
  expect() {
    local old="$1" new="$2" want="$3"
    local status=0
    check_news "$old" "$new" "${tmp}/NEWS.md" >/dev/null 2>&1 || status=$?
    if [ "$status" -ne "$want" ]; then
      echo "FAIL ${old} -> ${new} want exit ${want} got ${status}" >&2
      failed=1
    fi
  }
  write_news <<'EOF'
## Unreleased

### Planned breaking (next minor)

- later

## 0.10.2

- a fix
EOF
  expect 0.10.1 0.10.2 0

  write_news <<'EOF'
## 0.10.2

### Breaking

- no
EOF
  expect 0.10.1 0.10.2 1

  write_news <<'EOF'
## 0.10.2

### Planned breaking (next minor)

- stays a warning
EOF
  expect 0.10.1 0.10.2 0

  write_news <<'EOF'
## 0.11.0

### Breaking

- flags
EOF
  expect 0.10.1 0.11.0 0

  write_news <<'EOF'
## 0.11.0

- forgot the heading
EOF
  expect 0.10.1 0.11.0 1

  write_news <<'EOF'
## Unreleased

- still here
EOF
  expect 0.10.1 0.10.2 1

  write_news <<'EOF'
## 0.10.0

### Breaking

- older
EOF
  expect 0.10.1 0.11.0 1

  write_news <<'EOF'
## 0.10.0

### Breaking

- queue
EOF
  expect 0.9.4 0.10.0 0

  write_news <<'EOF'
## 0.2.0

### Breaking

- dropped -DEV
EOF
  expect 0.2.0-DEV 0.2.0 0

  write_news <<'EOF'
## 0.1.7

- dropped a patch prerelease
EOF
  expect 0.1.7-DEV 0.1.7 0

  write_news <<'EOF'
## 1.0.0

### Breaking

- first stable
EOF
  expect 0.10.1 1.0.0 0

  write_news <<'EOF'
## 1.2.4

- a patch above 1.0
EOF
  expect 1.2.3 1.2.4 1

  rm -rf "$tmp"
  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
  echo "release-news self-test ok"
}

ver_string() {
  git cat-file -p "${1}:Project.toml" \
    | sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1
}

# Best-effort. A git or API failure prints nothing and does not fail the cut.
warn_breaking_prs() {
  local base="$1" head="$2"
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  [ -n "$token" ] || return 0
  [ -n "${GITHUB_REPOSITORY:-}" ] || return 0
  if [ -f "$(git rev-parse --git-path shallow)" ]; then
    git fetch --unshallow origin >/dev/null 2>&1 || return 0
  fi
  local tag subjects
  tag="$(git describe --tags --abbrev=0 --match 'v*' "$base" 2>/dev/null || true)"
  [ -n "$tag" ] || return 0
  subjects="$(git log --format=%s "${tag}..${head}" 2>/dev/null || true)"
  [ -n "$subjects" ] || return 0
  local nums n labels line
  nums="$(printf '%s\n' "$subjects" | sed -n 's/.*(#\([0-9][0-9]*\))[[:space:]]*$/\1/p' | sort -u)"
  [ -n "$nums" ] || return 0
  local rows=""
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if ! labels="$(gh api --jq '[.labels[].name] | join(",")' "repos/${GITHUB_REPOSITORY}/issues/${n}" 2>/dev/null)"; then
      return 0
    fi
    rows="${rows}${n} ${labels}"$'\n'
  done <<<"$nums"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    n="${line%% *}"
    labels="${line#* }"
    case ",${labels}," in
      *,breaking,*)
        echo "::warning::PR #${n} is labeled breaking. If that change is still in this tree, raise the minor."
        ;;
    esac
  done <<<"$rows"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

old_ref="${1:?old ref}"
new_ref="${2:?new ref}"
news="$(mktemp)"
trap 'rm -f "$news"' EXIT
git cat-file -p "${new_ref}:NEWS.md" >"$news"
status=0
check_news "$(ver_string "$old_ref")" "$(ver_string "$new_ref")" "$news" || status=$?
warn_breaking_prs "$old_ref" "$new_ref" || true
exit "$status"
