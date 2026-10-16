# Pull request

## Summary

<!-- What / why -->
<!-- Type label: closing issue (`Fixes #N`) if unique, else branch prefix
     (feat/ → enhancement, fix/ → bug, breaking/ → breaking,
     chore/ docs/ ci/ test/ → chore), else a Conventional Commit title
     (fix: → bug, feat: → enhancement, ! → breaking,
     docs/ test/ ci/ chore: → chore). Else chore when the diff has no
     src/, ext/, or root Project.toml. Anything else fails the check.
     Version cuts use cut instead of a type label. Override with gh pr
     edit. -->

## Checklist

- [ ] Breaking status is correct — a change PR has the `breaking` label
      when needed; a cut PR has the NEWS structure required by its version
      bump. Breaking includes CLI behavior: flags, confirmation, exit codes,
      what is deleted. See
      [docs/src/developers/releasing.md](https://github.com/yamanori99/DistSSHKit.jl/blob/main/docs/src/developers/releasing.md).
- [ ] Version raise — `Project.toml` `version` went up (CI reads the
      diff; register when the remaining required checks are green)
- [ ] Remote / smoke tested if this PR needs it
