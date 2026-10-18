# Compile bench

Precompile time, load time, CLI wall time, the size of `src/**/*.jl`,
and the host. DistSSHKit, DistSSHQueue, and DistSSHRun each keep their
own record. The scripts live in that repo at `bench/compile/`.

The numbers that last are on the `bench-data` branch. The README on
that branch is a window of the latest 12 samples per Julia slot. The
files under `history/` are the archive. Nothing in the job deletes an
old file.

| Package | Archive |
| --- | --- |
| DistSSHKit | [bench-data](https://github.com/yamanori99/DistSSHKit.jl/tree/bench-data) |
| DistSSHQueue | [bench-data](https://github.com/yamanori99/DistSSHQueue.jl/tree/bench-data) |
| DistSSHRun | [bench-data](https://github.com/yamanori99/DistSSHRun.jl/tree/bench-data) |

When the job runs is in that repo's `CONTRIBUTING.md`, under Scheduled
CI. A run on `main` appends a sample and rebuilds the README. Any other
ref uploads the sample as an artifact and does not push. A command that
exits nonzero stops the run before a sample is written.

```bash
git clone --branch bench-data --single-branch \
  https://github.com/yamanori99/DistSSHKit.jl.git kit-bench-data
```

## Files

```text
history/<slot>/<YYYY-MM-DD>-<shortsha>.toml
README.md
```

`<slot>` is the CI name, such as `1.13` or `1.14-nightly`. The name
moves when the CI slot moves. Each file stores `julia` and
`julia_commit`, so a later slot can still be lined up with an earlier
one.

The file name is the UTC date and the first 7 characters of the commit.
Two runs of the same commit on the same UTC date keep the later file.
Sort by the `time` field inside the file, not by the file name alone,
when two samples share a date.

## Fields

| Field | Meaning |
| --- | --- |
| `time` | UTC time the sample was written (`YYYY-MM-DDTHH:MM:SSZ`) |
| `repo` | Package name |
| `version` | `Project.toml` `version` |
| `commit` | Full git commit |
| `slot` | CI Julia slot |
| `julia`, `julia_commit` | The Julia that ran the sample |
| `os` | Kernel name (`Linux`, `Darwin`) |
| `os_name` | OS name and version. Older files may omit this |
| `arch` | `x86_64` or `aarch64`. Older files may omit this |
| `cpu`, `threads` | Runner CPU |
| `src_files`, `src_lines` | `src/**/*.jl` file count and physical lines |
| `src_code_lines` | Those lines with blanks dropped |
| `src_bytes` | Bytes of those files |
| `precompile_full_sec` | `Pkg.precompile` of the fresh depot |
| `precompile_pkg_sec` | `Base.compilecache` of this package alone |
| `using_sec` | Wall time of `using` |
| `imports` | `@time_imports` rows whose name starts with `DistSSH` |
| `commands` | One row per CLI command in `bench/compile/commands.toml` |

A command row has `name`, `args`, `exit`, `wall_sec` (median of three
runs), `walls_sec`, `total_ms`, `main_ms`, `count`, `buckets`, and
`top` (the 20 slowest methods). DistSSHKit and DistSSHQueue record
`help` and `status`. DistSSHRun records `help`.

## Reading a long series

Keep samples with the same `os_name` and `arch` in one series. A host
change moves the times without a code change. `cpu` is there for the
same reason: GitHub changes the runner image.

`code lines` is the size to set next to a time jump. `src_lines` still
counts blank lines.

The README flags the latest sample against the previous one on the same
slot when the host OS or arch changes, package precompile grows by
1.5x and 0.5s, a command wall grows by 1.5x and 1s, or a method of at
least 200 ms is new in the top 20 or doubles. The flag does not fail
CI. A jump against a sample from months ago is a question for the
files, not for that flag.

One chart point is a bar. Two or more are a line. The chart only draws
the samples in the README window.
