category: planned

- `-y`, `--yes`, and `DISTSSHKIT_YES` will stop authorizing
  `setup --delete`, `setup --prune`, and `teardown`. Without
  `--confirm-path`, `-y` will exit 1. A `teardown` that was not asked to
  delete still prints `Would remove` and exits 0. `up default` still
  honors `DISTSSHKIT_YES`. DistSSHKit 0.11 (DistSSHRun 0.2, DistSSHQueue 0.10).
  `KitSession` `yes=true` is outside this change. `setup!(session, :delete)`
  and `setup!(session, :prune)` without `confirm_path` still follow `session.yes`.
