# Pull request

## Summary

<!-- What / why -->

## Testing

<!-- The command that ran, and what it returned. If nothing ran, say why. -->

## Risk

<!-- Name what this can break. Do not grade it. -->

## Revert

<!-- How to undo this after it merges. -->

## Checklist

- [ ] Breaking status is correct — a change PR has the `breaking` label
      when needed, and a `changelog.d/` fragment with `category: breaking`.
      A cut PR runs `./.github/news-collect.sh` and keeps the NEWS section
      required by its version bump. Breaking includes CLI behavior: flags,
      confirmation, exit codes, what is deleted. See
      [DistSSHKit releasing](https://github.com/yamanori99/DistSSHKit.jl/blob/main/docs/src/developers/releasing.md).
- [ ] News fragment — this PR adds one `changelog.d/*.md` file when it
      changes `src/`, `lib/**/src/`, or `ext/`. Docs, tests, and CI do not
      need one. A cut PR assembles fragments and does not add a new one.
- [ ] Version is correct — `Project.toml` `version` went up when this
      should ship, and stayed when it should not (CI reads the diff;
      register when the remaining required checks are green)
- [ ] Remote / smoke is done, or this change does not need it
