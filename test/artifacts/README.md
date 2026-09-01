# Test artifacts

Runtime files from tests (`ssh-e2e/` is gitignored).

## SSH E2E

```bash
open "$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt"
```

`SUMMARY.txt` lists each step and its log under `logs/`. Timestamped
`<UTC>_suite/` dirs stay (gitignored) so you can compare and retry. Wipe
`test/artifacts/ssh-e2e` only if disk hurts.

```text
test/artifacts/ssh-e2e/<UTC>_suite/
  SUMMARY.txt
  logs/
    01_….log
    02_….log
    …
```
