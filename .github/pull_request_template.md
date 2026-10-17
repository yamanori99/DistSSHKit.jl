# Pull request

## Summary

<!-- What / why -->

## Testing

<!-- The command that ran, and what it returned. If nothing ran, say why. -->

## Risk

<!-- What this change can break. Docs-only and comment-only changes are low. -->

## Revert

<!-- How to undo this after it merges. -->

## Checklist

- [ ] Breaking status is correct — a change PR has the `breaking` label
      when needed; a cut PR has the NEWS structure required by its version
      bump. Breaking includes CLI behavior: flags, confirmation, exit codes,
      what is deleted. See
      [docs/src/developers/releasing.md](https://github.com/yamanori99/DistSSHKit.jl/blob/main/docs/src/developers/releasing.md).
- [ ] Version raise — `Project.toml` `version` went up (CI reads the
      diff; register when the remaining required checks are green)
- [ ] Remote / smoke tested if this PR needs it
