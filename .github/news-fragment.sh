#!/usr/bin/env bash
# On a pull request that is not a version cut, require changelog fragments.
# A change under src/**, lib/**/src/**, or ext/** needs one valid fragment.
# Dependabot is exempt. The breaking label and a category: breaking
# fragment are both present or both absent. planned does not need it.
# Usage: ./.github/news-fragment.sh BASE HEAD
#        ./.github/news-fragment.sh --self-test
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

die() {
  echo "$1" >&2
  exit 1
}

path_needs_fragment() {
  local path="$1"
  case "$path" in
    src/*|ext/*) return 0 ;;
  esac
  if [[ "$path" =~ ^lib/(.+/)?src/.+ ]]; then
    return 0
  fi
  return 1
}

# list file lines are STATUS<TAB>PATH from git diff --name-status.
# label file is one label name per line. Empty is allowed.
evaluate_list() {
  local root="$1" listfile="$2" labelfile="$3" author="$4"
  if [ "$author" = "dependabot[bot]" ]; then
    echo "Dependabot is exempt from the news fragment check."
    return 0
  fi
  local need=0 fragments=0 breaking_frags=0
  local status path cat
  while IFS=$'\t' read -r status path; do
    [ -n "${status:-}" ] || continue
    [ -n "${path:-}" ] || continue
    if path_needs_fragment "$path"; then
      need=1
    fi
    case "$path" in
      changelog.d/*.md) ;;
      *) continue ;;
    esac
    case "$status" in
      A|M|T) ;;
      *) continue ;;
    esac
    if ! cat="$("${SCRIPT_DIR}/news-collect.sh" --validate-file "${root}/${path}")"; then
      return 1
    fi
    fragments=$((fragments + 1))
    if [ "$cat" = "breaking" ]; then
      breaking_frags=$((breaking_frags + 1))
    fi
  done <"$listfile"

  if [ "$need" -eq 1 ] && [ "$fragments" -eq 0 ]; then
    echo "This pull request changes src/, lib/**/src/, or ext/ and needs a changelog.d fragment." >&2
    return 1
  fi

  local has_label=0 name
  if [ -f "$labelfile" ]; then
    while IFS= read -r name; do
      if [ "$name" = "breaking" ]; then
        has_label=1
      fi
    done <"$labelfile"
  fi
  if [ "$has_label" -eq 1 ] && [ "$breaking_frags" -eq 0 ]; then
    echo "The breaking label needs a changelog.d fragment with category: breaking." >&2
    return 1
  fi
  if [ "$breaking_frags" -gt 0 ] && [ "$has_label" -eq 0 ]; then
    echo "A category: breaking fragment needs the breaking label." >&2
    return 1
  fi
  echo "news fragment check ok"
  return 0
}

ensure_commit() {
  local ref="$1"
  git -C "$ROOT" cat-file -e "${ref}^{commit}" 2>/dev/null && return 0
  if ! git -C "$ROOT" fetch --depth=1 origin "$ref"; then
    if [ -n "${PR:-}" ]; then
      git -C "$ROOT" fetch --depth=1 origin "refs/pull/${PR}/head" || true
    fi
  fi
  git -C "$ROOT" cat-file -e "${ref}^{commit}"
}

write_name_status() {
  local base="$1" head="$2" dest="$3" raw status path
  raw="$(mktemp)"
  git -C "$ROOT" diff --name-status --no-renames -z "$base" "$head" >"$raw"
  : >"$dest"
  while IFS= read -r -d '' status && IFS= read -r -d '' path; do
    printf '%s\t%s\n' "$status" "$path" >>"$dest"
  done <"$raw"
  rm -f "$raw"
}

run_check() {
  local base="$1" head="$2"
  if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    die "GITHUB_REPOSITORY is required"
  fi
  if [ -z "${PR:-}" ]; then
    die "PR is required"
  fi
  ensure_commit "$base"
  ensure_commit "$head"
  local author labels list labels_file err
  if ! author="$(gh api --jq .user.login "repos/${GITHUB_REPOSITORY}/pulls/${PR}")"; then
    die "Could not read the pull request author."
  fi
  if ! labels="$(gh api --jq '.labels[].name' "repos/${GITHUB_REPOSITORY}/issues/${PR}")"; then
    die "Could not read pull request labels."
  fi
  list="$(mktemp)"
  labels_file="$(mktemp)"
  printf '%s\n' "$labels" >"$labels_file"
  write_name_status "$base" "$head" "$list"
  err=0
  evaluate_list "$ROOT" "$list" "$labels_file" "$author" || err=$?
  rm -f "$list" "$labels_file"
  return "$err"
}

self_test() {
  local failed=0 tmp root list labels
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

  new_case() {
    root="$tmp/tree"
    rm -rf "$root"
    mkdir -p "$root/changelog.d" "$root/src" "$root/lib/Foo/src" "$root/ext/Bar" "$root/docs/src"
    list="$tmp/list"
    labels="$tmp/labels"
    : >"$list"
    : >"$labels"
  }
  add_row() {
    printf '%s\t%s\n' "$1" "$2" >>"$list"
  }
  frag() {
    local path="$1" category="$2" text="$3"
    mkdir -p "$(dirname "$root/$path")"
    printf 'category: %s\n\n%s\n' "$category" "$text" >"$root/$path"
  }

  new_case
  add_row M src/app.jl
  frag changelog.d/help-word.md fixed "- fixed the word"
  add_row A changelog.d/help-word.md
  expect_ok src-and-fixed evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M src/app.jl
  expect_fail src-without-fragment evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M docs/src/index.md
  add_row M README.md
  expect_ok docs-only evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row A src/new.jl
  expect_ok dependabot evaluate_list "$root" "$list" "$labels" "dependabot[bot]"

  new_case
  add_row M src/app.jl
  frag changelog.d/break-flag.md breaking "- drops a flag"
  add_row A changelog.d/break-flag.md
  printf '%s\n' breaking >"$labels"
  expect_ok breaking-pair evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M src/app.jl
  frag changelog.d/help-word.md fixed "- fixed the word"
  add_row A changelog.d/help-word.md
  printf '%s\n' breaking >"$labels"
  expect_fail label-without-fragment evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M src/app.jl
  frag changelog.d/break-flag.md breaking "- drops a flag"
  add_row A changelog.d/break-flag.md
  expect_fail fragment-without-label evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M lib/Foo/src/a.jl
  frag changelog.d/soon.md planned "- will change"
  add_row A changelog.d/soon.md
  expect_ok planned-no-label evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M lib/Foo/test/a.jl
  expect_ok lib-test-only evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row A ext/Bar/ext.jl
  frag changelog.d/quiet.md skip "not user visible"
  add_row A changelog.d/quiet.md
  expect_ok ext-skip evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row A ext/Bar/ext.jl
  printf 'category: skip\n\none\ntwo\n' >"$root/changelog.d/quiet.md"
  add_row A changelog.d/quiet.md
  expect_fail skip-two-lines evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M src/app.jl
  printf 'category: fixed\npackage: Example\n\n- x\n' >"$root/changelog.d/bad.md"
  add_row A changelog.d/bad.md
  expect_fail package-field evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row D src/app.jl
  expect_fail deleted-src evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M src/app.jl
  frag changelog.d/help-word.md fixed "- fixed the word"
  # Present on the tree but not in the diff: does not satisfy the pull request.
  expect_fail fragment-not-in-diff evaluate_list "$root" "$list" "$labels" "octocat"

  new_case
  add_row M lib/src/a.jl
  frag changelog.d/help-word.md fixed "- fixed the word"
  add_row A changelog.d/help-word.md
  expect_ok lib-src evaluate_list "$root" "$list" "$labels" "octocat"

  # git diff plus the author and label API, with gh stubbed on PATH.
  git -C "$tmp" init -q -b main repo2
  git -C "$tmp/repo2" config user.email "test@example.com"
  git -C "$tmp/repo2" config user.name "test"
  mkdir -p "$tmp/repo2/src" "$tmp/bin"
  printf 'v1\n' >"$tmp/repo2/src/app.jl"
  git -C "$tmp/repo2" add src/app.jl
  git -C "$tmp/repo2" commit -q -m base
  local base_sha head_sha saved_root saved_path
  base_sha="$(git -C "$tmp/repo2" rev-parse HEAD)"
  printf 'v2\n' >"$tmp/repo2/src/app.jl"
  mkdir -p "$tmp/repo2/changelog.d"
  printf 'category: fixed\n\n- fixed the word\n' >"$tmp/repo2/changelog.d/help-word.md"
  git -C "$tmp/repo2" add src/app.jl changelog.d/help-word.md
  git -C "$tmp/repo2" commit -q -m head
  head_sha="$(git -C "$tmp/repo2" rev-parse HEAD)"
  cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
url=""
for arg in "$@"; do
  url="$arg"
done
case "$url" in
  */pulls/*)
    printf '%s\n' 'octocat'
    ;;
  */issues/*)
    printf '%s\n' 'chore'
    ;;
  *)
    echo "unexpected gh url: $url" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$tmp/bin/gh"
  saved_root="$ROOT"
  saved_path="$PATH"
  ROOT="$tmp/repo2"
  PATH="$tmp/bin:${PATH}"
  PR=7
  GITHUB_REPOSITORY=example/repo
  expect_ok git-diff-direct run_check "$base_sha" "$head_sha"
  PATH="$saved_path"
  ROOT="$saved_root"
  unset PR GITHUB_REPOSITORY

  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
  echo "news-fragment self-test ok"
}

case "${1:-}" in
  --self-test)
    self_test
    exit 0
    ;;
  "")
    die "usage: ./.github/news-fragment.sh BASE HEAD"
    ;;
  *)
    if [ "$#" -ne 2 ]; then
      die "usage: ./.github/news-fragment.sh BASE HEAD"
    fi
    run_check "$1" "$2"
    ;;
esac
