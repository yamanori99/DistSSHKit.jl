#!/usr/bin/env bash
# Build NEWS.md from changelog.d/*.md on a version cut.
# A fragment is one file. The first line is
#   category: breaking|planned|added|fixed|changed|skip
# then a blank line, then the bullet. skip is one reason line and is not
# copied into NEWS.md. No other fields.
# With no arguments, rewrite NEWS.md for the Project.toml version, delete
# breaking/changed/added/fixed/skip fragments, and keep planned fragments.
# --check fails unless that rewrite is already done.
# --validate-file PATH prints the category of one fragment.
# Usage: ./.github/news-collect.sh
#        ./.github/news-collect.sh --check
#        ./.github/news-collect.sh --validate-file PATH
#        ./.github/news-collect.sh --self-test
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

die() {
  echo "$1" >&2
  exit 1
}

fragment_error() {
  local base="$1" rc="$2"
  case "$rc" in
    2) echo "fragment ${base}: first line must be 'category: breaking|planned|added|fixed|changed|skip'" >&2 ;;
    3) echo "fragment ${base}: second line must be blank" >&2 ;;
    4) echo "fragment ${base}: missing text after the blank line" >&2 ;;
    5) echo "fragment ${base}: skip needs one reason line" >&2 ;;
    6) echo "fragment ${base}: text must start with '- '" >&2 ;;
    7) echo "fragment ${base}: a line must not start with '## '" >&2 ;;
    8) echo "fragment ${base}: CR is not allowed" >&2 ;;
    9) echo "fragment ${base}: category line must be followed by a blank line" >&2 ;;
    *) echo "fragment ${base}: invalid (${rc})" >&2 ;;
  esac
}

# Print the category. Write the bullet text to body_out.
extract_fragment() {
  local file="$1" body_out="$2"
  local base cat_out awk_rc
  base="$(basename "$file")"
  if [[ ! "$base" =~ ^[a-z0-9][a-z0-9.-]{0,60}\.md$ ]]; then
    echo "fragment name must match [a-z0-9][a-z0-9.-]{0,60}.md: ${base}" >&2
    return 1
  fi
  if [ ! -f "$file" ]; then
    echo "fragment not found: ${base}" >&2
    return 1
  fi
  awk_rc=0
  cat_out="$(
    awk -v body="$body_out" '
      BEGIN { code = 0; n = 0; saw2 = 0; cat = "" }
      index($0, "\r") != 0 { code = 8; exit }
      NR == 1 {
        if ($0 !~ /^category: (breaking|planned|added|fixed|changed|skip)$/) {
          code = 2
          exit
        }
        cat = substr($0, 11)
        next
      }
      NR == 2 {
        saw2 = 1
        if ($0 != "") {
          code = 3
          exit
        }
        next
      }
      { text[++n] = $0 }
      END {
        if (code != 0) exit code
        if (cat == "") exit 2
        if (!saw2) exit 9
        while (n > 0 && text[n] == "") n--
        if (n < 1) exit 4
        for (i = 1; i <= n; i++) if (text[i] ~ /^## /) exit 7
        if (cat == "skip") {
          if (n != 1 || text[1] == "") exit 5
        } else if (text[1] !~ /^- /) exit 6
        for (i = 1; i <= n; i++) print text[i] > body
        print cat
      }
    ' "$file"
  )" || awk_rc=$?
  if [ "$awk_rc" -ne 0 ]; then
    fragment_error "$base" "$awk_rc"
    return 1
  fi
  printf '%s\n' "$cat_out"
}

project_version() {
  local ver
  ver="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${ROOT}/Project.toml" | head -n 1)"
  if [ -z "$ver" ]; then
    echo "Project.toml has no version." >&2
    return 1
  fi
  printf '%s\n' "$ver"
}

# Fill the body arrays and consumable_files from changelog.d.
load_fragments() {
  breaking_bodies=()
  changed_bodies=()
  added_bodies=()
  fixed_bodies=()
  planned_bodies=()
  consumable_files=()
  local dir="${ROOT}/changelog.d"
  if [ ! -d "$dir" ]; then
    return 0
  fi
  local listing path cat body tmp
  local -a paths
  listing="$(mktemp)"
  tmp="$(mktemp)"
  find "$dir" -maxdepth 1 -type f -name '*.md' -print | LC_ALL=C sort >"$listing"
  paths=()
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    paths+=("$path")
  done <"$listing"
  rm -f "$listing"
  for path in "${paths[@]}"; do
    if ! cat="$(extract_fragment "$path" "$tmp")"; then
      rm -f "$tmp"
      return 1
    fi
    body="$(cat "$tmp")"
    case "$cat" in
      breaking)
        breaking_bodies+=("$body")
        consumable_files+=("$path")
        ;;
      changed)
        changed_bodies+=("$body")
        consumable_files+=("$path")
        ;;
      added)
        added_bodies+=("$body")
        consumable_files+=("$path")
        ;;
      fixed)
        fixed_bodies+=("$body")
        consumable_files+=("$path")
        ;;
      planned)
        planned_bodies+=("$body")
        ;;
      skip)
        consumable_files+=("$path")
        ;;
      *)
        rm -f "$tmp"
        echo "fragment $(basename "$path"): unknown category ${cat}" >&2
        return 1
        ;;
    esac
  done
  rm -f "$tmp"
}

emit_bodies() {
  local body
  for body in "$@"; do
    printf '%s\n\n' "$body"
  done
}

write_unreleased() {
  local dest="$1"
  {
    printf '%s\n' '## Unreleased'
    printf '\n'
    # shellcheck disable=SC2016 # backticks are Markdown, not command substitution
    printf '%s\n' 'Notes since the last release are files in `changelog.d/`.'
    printf '%s\n' 'The version-cut PR copies them into this file.'
    printf '\n'
    printf '%s\n' '### Planned breaking (next minor)'
    printf '\n'
    if [ "${#planned_bodies[@]}" -gt 0 ]; then
      emit_bodies "${planned_bodies[@]}"
    fi
  } >"$dest"
}

write_release() {
  local dest="$1" version="$2"
  {
    printf '## %s\n' "$version"
    printf '\n'
    if [ "${#breaking_bodies[@]}" -gt 0 ]; then
      printf '%s\n' '### Breaking'
      printf '\n'
      emit_bodies "${breaking_bodies[@]}"
    fi
    if [ "${#changed_bodies[@]}" -gt 0 ]; then
      emit_bodies "${changed_bodies[@]}"
    fi
    if [ "${#added_bodies[@]}" -gt 0 ]; then
      emit_bodies "${added_bodies[@]}"
    fi
    if [ "${#fixed_bodies[@]}" -gt 0 ]; then
      emit_bodies "${fixed_bodies[@]}"
    fi
  } >"$dest"
}

release_bullet_count() {
  local n=0
  n=$((n + ${#breaking_bodies[@]} + ${#changed_bodies[@]} + ${#added_bodies[@]} + ${#fixed_bodies[@]}))
  printf '%s\n' "$n"
}

# Split NEWS.md into prefix (before ## Unreleased), the Unreleased block,
# and the suffix (from the next level-2 heading through EOF).
split_news() {
  local news="$1" prefix="$2" unrel="$3" suffix="$4"
  : >"$prefix"
  : >"$unrel"
  : >"$suffix"
  awk -v prefix="$prefix" -v unrel="$unrel" -v suffix="$suffix" '
    BEGIN { state = "pre" }
    state == "pre" && $0 == "## Unreleased" {
      state = "unrel"
      print > unrel
      next
    }
    state == "unrel" && $0 ~ /^## / {
      state = "suf"
    }
    state == "pre" { print > prefix }
    state == "unrel" { print > unrel }
    state == "suf" { print > suffix }
  ' "$news"
}

section_has_bullet() {
  local version="$1" news="$2"
  awk -v ver="$version" '
    BEGIN { state = 0; hit = 0 }
    $0 == "## " ver { state = 1; next }
    state && $0 ~ /^## / { exit }
    state && $0 ~ /^- / { hit = 1; exit }
    END { exit !hit }
  ' "$news"
}

assemble_news() {
  local version="$1" dest="$2"
  local news="${ROOT}/NEWS.md"
  local prefix unrel suffix release
  if [ ! -f "$news" ]; then
    echo "NEWS.md is missing." >&2
    return 1
  fi
  if ! grep -qx '## Unreleased' "$news"; then
    echo "NEWS.md has no ## Unreleased section." >&2
    return 1
  fi
  if grep -qx "## ${version}" "$news"; then
    echo "NEWS.md already has ## ${version}." >&2
    return 1
  fi
  prefix="$(mktemp)"
  unrel="$(mktemp)"
  suffix="$(mktemp)"
  release="$(mktemp)"
  split_news "$news" "$prefix" "$unrel" "$suffix"
  write_unreleased "$unrel"
  write_release "$release" "$version"
  cat "$prefix" "$unrel" "$release" "$suffix" >"$dest"
  rm -f "$prefix" "$unrel" "$suffix" "$release"
}

main_mutate() {
  local version count dest
  version="$(project_version)"
  load_fragments
  count="$(release_bullet_count)"
  if [ "$count" -eq 0 ]; then
    echo "No breaking, changed, added, or fixed fragments for ## ${version}." >&2
    return 1
  fi
  dest="$(mktemp)"
  if ! assemble_news "$version" "$dest"; then
    rm -f "$dest"
    return 1
  fi
  mv "$dest" "${ROOT}/NEWS.md"
  if [ "${#consumable_files[@]}" -gt 0 ]; then
    rm -f "${consumable_files[@]}"
  fi
  echo "Collected changelog.d into NEWS.md ## ${version}."
}

main_check() {
  local version news expected actual
  version="$(project_version)"
  news="${ROOT}/NEWS.md"
  load_fragments
  if [ "${#consumable_files[@]}" -gt 0 ]; then
    echo "changelog.d still has fragments a version cut must consume:" >&2
    local path
    for path in "${consumable_files[@]}"; do
      echo "  $(basename "$path")" >&2
    done
    return 1
  fi
  if [ ! -f "$news" ]; then
    echo "NEWS.md is missing." >&2
    return 1
  fi
  expected="$(mktemp)"
  actual="$(mktemp)"
  local prefix suffix
  prefix="$(mktemp)"
  suffix="$(mktemp)"
  split_news "$news" "$prefix" "$actual" "$suffix"
  if [ ! -s "$actual" ]; then
    rm -f "$expected" "$actual" "$prefix" "$suffix"
    echo "NEWS.md has no ## Unreleased section." >&2
    return 1
  fi
  write_unreleased "$expected"
  if ! cmp -s "$expected" "$actual"; then
    echo "NEWS.md ## Unreleased does not match the planned fragments." >&2
    diff -u "$expected" "$actual" >&2 || true
    rm -f "$expected" "$actual" "$prefix" "$suffix"
    return 1
  fi
  rm -f "$expected" "$actual" "$prefix" "$suffix"
  if ! section_has_bullet "$version" "$news"; then
    echo "NEWS.md section ## ${version} has no bullet." >&2
    return 1
  fi
  echo "NEWS.md ## ${version} matches the collected fragments."
}

validate_cli() {
  local file="$1" tmp cat
  tmp="$(mktemp)"
  if ! cat="$(extract_fragment "$file" "$tmp")"; then
    rm -f "$tmp"
    exit 1
  fi
  rm -f "$tmp"
  printf '%s\n' "$cat"
}

self_test() {
  local failed=0 tmp repo
  SELF_TMP="$(mktemp -d)"
  tmp="$SELF_TMP"
  # Invoked by the EXIT trap below.
  # shellcheck disable=SC2329
  cleanup_self() {
    if [ -n "${SELF_TMP:-}" ]; then
      rm -rf "$SELF_TMP"
    fi
  }
  trap cleanup_self EXIT

  write_frag() {
    local path="$1" category="$2"
    shift 2
    {
      printf 'category: %s\n' "$category"
      printf '\n'
      printf '%s\n' "$@"
    } >"$path"
  }

  setup_repo() {
    repo="$tmp/repo"
    rm -rf "$repo"
    mkdir -p "$repo/changelog.d"
    cat >"$repo/Project.toml" <<'EOF'
name = "Example"
version = "0.2.0"
EOF
    cat >"$repo/NEWS.md" <<'EOF'
# News

## Unreleased

- old note

### Planned breaking (next minor)

- old plan

## 0.1.0

- previous

### Breaking

- old break stays
EOF
  }

  expect_fail() {
    local name="$1"
    shift
    local err
    err="$(mktemp)"
    if "$@" >"$err" 2>&1; then
      echo "FAIL ${name} expected non-zero" >&2
      cat "$err" >&2
      failed=1
    fi
    rm -f "$err"
  }

  expect_ok() {
    local name="$1"
    shift
    local err
    err="$(mktemp)"
    if ! "$@" >"$err" 2>&1; then
      echo "FAIL ${name} expected zero" >&2
      cat "$err" >&2
      failed=1
    fi
    rm -f "$err"
  }

  # Passed to expect_ok / expect_fail by name.
  # shellcheck disable=SC2329
  run_at() {
    local root="$1"
    shift
    (
      ROOT="$root"
      "$@"
    )
  }

  setup_repo
  write_frag "$repo/changelog.d/z-breaking.md" breaking "- break item"
  write_frag "$repo/changelog.d/a-fixed.md" fixed "- fix a" "  continued"
  write_frag "$repo/changelog.d/c-fixed.md" fixed "- fix c"
  write_frag "$repo/changelog.d/m-added.md" added "- add item"
  write_frag "$repo/changelog.d/b-changed.md" changed "- change item"
  write_frag "$repo/changelog.d/e-plan.md" planned "- plan item"
  write_frag "$repo/changelog.d/f-skip.md" skip "not user visible"

  expect_ok mutate run_at "$repo" main_mutate
  if [ -e "$repo/changelog.d/z-breaking.md" ] || [ -e "$repo/changelog.d/f-skip.md" ] \
    || [ -e "$repo/changelog.d/a-fixed.md" ]; then
    echo "FAIL mutate left a consumed fragment" >&2
    failed=1
  fi
  if [ ! -f "$repo/changelog.d/e-plan.md" ]; then
    echo "FAIL mutate removed a planned fragment" >&2
    failed=1
  fi
  cat >"$tmp/expected.md" <<'EOF'
# News

## Unreleased

Notes since the last release are files in `changelog.d/`.
The version-cut PR copies them into this file.

### Planned breaking (next minor)

- plan item

## 0.2.0

### Breaking

- break item

- change item

- add item

- fix a
  continued

- fix c

## 0.1.0

- previous

### Breaking

- old break stays
EOF
  if ! cmp -s "$tmp/expected.md" "$repo/NEWS.md"; then
    echo "FAIL mutate NEWS.md bytes" >&2
    diff -u "$tmp/expected.md" "$repo/NEWS.md" >&2 || true
    failed=1
  fi
  expect_ok check-after-mutate run_at "$repo" main_check

  # A second collect has nothing to release.
  expect_fail second-mutate run_at "$repo" main_mutate
  if ! cmp -s "$tmp/expected.md" "$repo/NEWS.md"; then
    echo "FAIL failed mutate rewrote NEWS.md" >&2
    failed=1
  fi

  setup_repo
  write_frag "$repo/changelog.d/z-breaking.md" breaking "- break item"
  printf '\n## 0.2.0\n\n- already\n' >>"$repo/NEWS.md"
  expect_fail duplicate-section run_at "$repo" main_mutate
  if [ ! -f "$repo/changelog.d/z-breaking.md" ]; then
    echo "FAIL duplicate section deleted the fragment" >&2
    failed=1
  fi

  setup_repo
  rm -rf "$repo/changelog.d"
  expect_fail empty run_at "$repo" main_mutate
  if ! grep -qx -- '- old note' "$repo/NEWS.md"; then
    echo "FAIL empty collect rewrote NEWS.md" >&2
    failed=1
  fi

  setup_repo
  write_frag "$repo/changelog.d/a-fixed.md" fixed "- kept"
  printf 'package: Example\n' >>"$repo/changelog.d/a-fixed.md"
  # package on line 2 is the rejected shape: rewrite the file explicitly.
  printf 'category: fixed\npackage: Example\n\n- kept\n' >"$repo/changelog.d/a-fixed.md"
  expect_fail package-field run_at "$repo" main_mutate

  printf 'category: fixed\n\n- has a heading\n## 9.9.9\n' >"$repo/changelog.d/a-fixed.md"
  expect_fail heading-line run_at "$repo" main_mutate

  printf 'category: skip\n\none\ntwo\n' >"$repo/changelog.d/a-fixed.md"
  expect_fail skip-two-lines run_at "$repo" main_mutate

  printf 'category: nope\n\n- x\n' >"$repo/changelog.d/a-fixed.md"
  expect_fail bad-category run_at "$repo" main_mutate

  printf 'category: fixed\n\nnot a bullet\n' >"$repo/changelog.d/a-fixed.md"
  expect_fail not-a-bullet run_at "$repo" main_mutate

  printf 'category: fixed\r\n\r\n- x\r\n' >"$repo/changelog.d/a-fixed.md"
  expect_fail cr run_at "$repo" main_mutate

  rm -f "$repo/changelog.d/a-fixed.md"
  printf 'category: fixed\n\n- x\n' >"$repo/changelog.d/Bad.md"
  expect_fail slug run_at "$repo" main_mutate

  # --check postcondition: planned text must be in Unreleased, and the
  # release section must contain a bullet.
  setup_repo
  write_frag "$repo/changelog.d/e-plan.md" planned "- plan item"
  cat >"$repo/NEWS.md" <<'EOF'
# News

## Unreleased

Notes since the last release are files in `changelog.d/`.
The version-cut PR copies them into this file.

### Planned breaking (next minor)

- plan item

## 0.2.0

- shipped

## 0.1.0

- previous
EOF
  expect_ok check-planned run_at "$repo" main_check

  printf 'category: fixed\n\n- late\n' >"$repo/changelog.d/a-fixed.md"
  expect_fail check-fixed-remains run_at "$repo" main_check
  rm -f "$repo/changelog.d/a-fixed.md"

  printf 'category: breaking\n\n- late\n' >"$repo/changelog.d/z-breaking.md"
  expect_fail check-breaking-remains run_at "$repo" main_check
  rm -f "$repo/changelog.d/z-breaking.md"

  printf 'category: skip\n\ninternal\n' >"$repo/changelog.d/f-skip.md"
  expect_fail check-skip-remains run_at "$repo" main_check
  rm -f "$repo/changelog.d/f-skip.md"

  cat >"$repo/NEWS.md" <<'EOF'
# News

## Unreleased

Notes since the last release are files in `changelog.d/`.
The version-cut PR copies them into this file.

### Planned breaking (next minor)

## 0.2.0

- shipped

## 0.1.0

- previous
EOF
  expect_fail check-unreleased-drift run_at "$repo" main_check

  cat >"$repo/NEWS.md" <<'EOF'
# News

## Unreleased

Notes since the last release are files in `changelog.d/`.
The version-cut PR copies them into this file.

### Planned breaking (next minor)

- plan item

## 0.2.0

### Breaking

## 0.1.0

- previous
EOF
  expect_fail check-empty-release run_at "$repo" main_check

  # Patch-shaped section with no ### Breaking still passes --check.
  # release-news.sh owns the bump class.
  cat >"$repo/NEWS.md" <<'EOF'
# News

## Unreleased

Notes since the last release are files in `changelog.d/`.
The version-cut PR copies them into this file.

### Planned breaking (next minor)

- plan item

## 0.2.0

- shipped without a breaking heading

## 0.1.0

- previous
EOF
  expect_ok check-no-breaking-heading run_at "$repo" main_check

  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
  echo "news-collect self-test ok"
}

case "${1:-}" in
  --self-test)
    self_test
    exit 0
    ;;
  --check)
    if [ "$#" -ne 1 ]; then
      die "usage: ./.github/news-collect.sh --check"
    fi
    main_check
    ;;
  --validate-file)
    if [ "$#" -ne 2 ]; then
      die "usage: ./.github/news-collect.sh --validate-file PATH"
    fi
    validate_cli "$2"
    ;;
  "")
    main_mutate
    ;;
  *)
    die "usage: ./.github/news-collect.sh [--check|--self-test|--validate-file PATH]"
    ;;
esac
