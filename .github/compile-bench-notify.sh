#!/usr/bin/env bash
# Open or close the one "Compile bench failed" issue.
# RESULT is the 1.13 job result. skipped (a push that is not a cut) does not close.
set -euo pipefail

result="${RESULT:?}"
case "$result" in
  failure | success) ;;
  *) exit 0 ;;
esac

title='Compile bench failed'
existing="$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --label alert --search "in:title $title" --json number --jq '.[0].number // empty')"
if [ "$result" = "failure" ]; then
  body="Latest run: ${RUN_URL:?}

The 1.13 compile bench on main failed, so that sample was not written. The 1.14-nightly slot is not part of this issue."
  gh label create alert --description "Auto: scheduled check failed (E2E weekly, CI weekly, Runic)" --color "ff4d00" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1 || true
  if [ -n "$existing" ]; then
    gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body"
  else
    gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --label alert --body "$body"
  fi
elif [ -n "$existing" ]; then
  gh issue close "$existing" --repo "$GITHUB_REPOSITORY" --reason completed --comment "Latest 1.13 compile bench on main succeeded: ${RUN_URL:?}"
fi
