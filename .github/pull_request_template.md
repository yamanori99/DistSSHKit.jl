# Pull request

**Type label required** (CI + PR comment until present): `bug` | `enhancement` | `breaking` | `chore`

```bash
gh pr edit $PR --add-label enhancement
```

Path labels (`area:*`, `docs`, `ci`) are automatic. Type labels are not.

## Summary

<!-- What / why -->
<!-- breaking = this PR breaks callers; use for release / version-cut triage -->

## Checklist

- [ ] Type label applied (`bug` / `enhancement` / `chore`; add `breaking` if callers change)
- [ ] Not breaking — or `breaking` label (version bump decided separately)
- [ ] Remote / smoke tested if this PR needs it
