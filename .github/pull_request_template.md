# Pull request

## Summary

<!-- What / why -->
<!-- Type label: closing issue (`Fixes #N`) if unique, else branch prefix
     (feat/ → enhancement, fix/ → bug, breaking/ → breaking,
     chore/ docs/ ci/ test/ → chore). Any other prefix fails the check.
     Override with gh pr edit. -->

## Checklist

- [ ] Not breaking — or `breaking` label. Breaking includes CLI behavior:
      flags, confirmation, exit codes, what is deleted. See
      [docs/src/developers/releasing.md](https://github.com/yamanori99/DistSSHKit.jl/blob/main/docs/src/developers/releasing.md).
- [ ] Version raise — `Project.toml` `version` went up (CI reads the
      diff; register when the remaining required checks are green)
- [ ] Remote / smoke tested if this PR needs it
