# Review

What failure looks like in this repository. Cap comments at bugs and
regressions in this diff. Style, diagnostics, and cleanup are out of
scope. Runic and JETLS already gate those.

Cite a file and a line in the diff. Do not guess from a name. Do not
repeat a finding already posted. A bug this pull request did not
introduce is pre-existing. Say so, and do not ask for it to be fixed
here.

Start the summary with the count of findings. When the count is zero,
say there is nothing to fix.

Skip `HISTORY.md` and `test/artifacts/**`.

## Failures

- **Docs lie.** A manual, README, or NEWS states a flag, confirmation,
  exit code, or deleted path that the code does not implement.
- **Config misroutes.** A required check name, the heavy-job allowlist,
  or a label rule sends a change to the wrong gate.
- **Remote shell.** A remote command interpolates a value without
  `_remote_sh_quote` or `_remote_shell_path_word`. `~` expansion belongs
  to `_remote_shell_path_word`.
- **Delete, prune, teardown.** A path calculation in this diff can remove
  a path the user did not confirm. `-y`, `--yes`, and `DISTSSHKIT_YES`
  still skip that prompt.
- **Public behavior.** Flags, confirmation, exit codes, or what is deleted
  changed, and the pull request is not labeled `breaking`, or that
  breaking change is mixed with another change.
- **Registrator.** The register command appears in an issue, a pull
  request body, or a pull request comment.
