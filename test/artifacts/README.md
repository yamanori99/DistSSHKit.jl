# Test artifacts

Runtime files from tests (`ssh-e2e/` is gitignored).

## SSH E2E

```bash
open "$(cat test/artifacts/ssh-e2e/LATEST)/SUMMARY.txt"
```

`SUMMARY.txt` lists each step and its log under `logs/`.

```text
test/artifacts/ssh-e2e/<UTC>_suite/
  SUMMARY.txt
  logs/
    01_….log
    02_….log
    …
```

```bash
rm -rf test/artifacts/ssh-e2e
```
