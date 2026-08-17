#!/usr/bin/env bash
# Backfill `area:*` on every PR from the current `.github/labeler.yml`.
# Replaces legacy path labels `docs` / `ci` with `area:docs` / `area:ci`.
# Does not touch type labels (`bug` / `enhancement` / `chore` / `breaking` /
# `cut` / `dependencies`). Issues are not scanned.
#
# Usage:
#   ./.github/retag-pr-areas.sh           # dry-run
#   ./.github/retag-pr-areas.sh --apply
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--apply]" >&2
  exit 2
fi

python3 - "$ROOT" "$APPLY" <<'PY'
import json
import re
import subprocess
import sys

root, apply = sys.argv[1], sys.argv[2] == "1"
yml_path = f"{root}/.github/labeler.yml"
text = open(yml_path, encoding="utf-8").read()

def to_re(glob):
    i, out = 0, []
    while i < len(glob):
        if glob.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
            continue
        if glob.startswith("**", i):
            out.append(".*")
            i += 2
            continue
        if glob[i] == "*":
            out.append("[^/]*")
            i += 1
            continue
        out.append(re.escape(glob[i]))
        i += 1
    return re.compile("^" + "".join(out) + "$")

by_label = {}
current = None
for line in text.splitlines():
    m = re.match(r'^"area:([^"]+)":\s*$', line)
    if m:
        current = "area:" + m.group(1)
        by_label.setdefault(current, [])
        continue
    m = re.match(r'^\s+- "([^"]+)"\s*$', line)
    if m and current:
        by_label[current].append(m.group(1))

compiled = {lab: [to_re(g) for g in globs] for lab, globs in by_label.items()}
if not compiled:
    print("no area:* rules in labeler.yml", file=sys.stderr)
    sys.exit(1)

LEGACY = {"docs": "area:docs", "ci": "area:ci"}


def gh_json(args):
    out = subprocess.check_output(["gh", *args], text=True)
    return json.loads(out) if out.strip() else []


def wanted_for(paths):
    hit = set()
    for lab, rxs in compiled.items():
        if any(rx.match(p) for p in paths for rx in rxs):
            hit.add(lab)
    return hit


prs = gh_json(
    [
        "pr",
        "list",
        "--state",
        "all",
        "--limit",
        "500",
        "--json",
        "number,labels,files",
    ]
)
changed = 0
for pr in sorted(prs, key=lambda p: p["number"]):
    n = pr["number"]
    paths = [f["path"] for f in (pr.get("files") or [])]

    wanted = wanted_for(paths)
    have = {lab["name"] for lab in pr.get("labels") or []}
    have_area = {x for x in have if x.startswith("area:")}
    add = sorted(wanted - have)
    remove = sorted((have_area - wanted) | (have & LEGACY.keys()))
    if not add and not remove:
        continue
    changed += 1
    print(f"#{n}  +{' '.join(add) or '—'}  -{' '.join(remove) or '—'}")
    if apply:
        cmd = ["gh", "pr", "edit", str(n)]
        if add:
            cmd += ["--add-label", ",".join(add)]
        if remove:
            cmd += ["--remove-label", ",".join(remove)]
        subprocess.check_call(cmd)

mode = "applied" if apply else "dry-run"
print(f"{mode}: {changed} / {len(prs)} PRs would change" if not apply else f"{mode}: {changed} / {len(prs)} PRs")
PY
