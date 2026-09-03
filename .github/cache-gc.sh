#!/usr/bin/env bash
# Keep the newest Actions cache per restore-key prefix (10 GB repo quota).
# Needs gh + GH_TOKEN with actions: write. Safe to re-run.
set -euo pipefail

# gh paginates; --limit is the max rows returned. Fail if we hit the cap so
# a full repo does not look "clean" while older caches remain.
LIMIT=10000
list_json="$(gh cache list --limit "$LIMIT" --json id,key,createdAt,lastAccessedAt)"
count="$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' <<<"$list_json")"
if (( count >= LIMIT )); then
  echo "cache-gc: hit --limit $LIMIT; raise LIMIT so every cache is listed" >&2
  exit 1
fi

ids_txt="$(python3 -c '
import json, sys

rows = json.load(sys.stdin)

def prefix(key: str) -> str:
    if ";run_id=" in key:
        return key.split(";run_id=", 1)[0]
    if key.startswith("wsl-julia-max-"):
        return "wsl-julia-max"
    if key.startswith("2:distributionDirectory"):
        return "2:distributionDirectory"
    return key

def stamp(row: dict) -> str:
    return row.get("lastAccessedAt") or row.get("createdAt") or ""

groups = {}
for row in rows:
    groups.setdefault(prefix(row["key"]), []).append(row)

for items in groups.values():
    items.sort(key=stamp, reverse=True)
    for old in items[1:]:
        print(old["id"])
' <<<"$list_json")"

if [[ -z "$ids_txt" ]]; then
  echo "cache-gc: nothing to delete"
  exit 0
fi
mapfile -t ids <<< "$ids_txt"

echo "cache-gc: deleting ${#ids[@]} old cache(s)"
fail=0
for id in "${ids[@]}"; do
  [[ -n "${id:-}" ]] || continue
  if ! gh cache delete "$id"; then
    echo "cache-gc: delete $id failed (already gone?)" >&2
    fail=1
  fi
done
if (( fail != 0 )); then
  echo "cache-gc: some deletes failed" >&2
  exit 1
fi
