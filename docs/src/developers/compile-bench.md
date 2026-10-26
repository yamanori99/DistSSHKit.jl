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
CI. A run on `main` appends a sample. A render job then rebuilds the
README and `bench.html` from the history already on `bench-data`, and copies
`bench.html` to the root of `gh-pages`. GitHub Pages serves that file as HTML.
A `main` push that
changes `bench/compile/report.jl` or `bench/compile/charts.jl` does the same and does not measure.
A pull request that changes that file renders the history into the job
summary and does not push. Every run uploads the sample as an artifact.
A ref other than `main` does not push. A command that
exits nonzero stops the run before a sample is written. A 1.13 failure
on `main` opens an issue titled `Compile bench failed`, with the `alert`
label. A later 1.13 success on `main` closes it. A skipped run, including
a `Project.toml` push that is not a version cut, does not close it. The
1.14-nightly and nightly slots stay out of that issue. The page
opens on 1.13. A solid line marks the sample where `version` changed.
On the 1.13 slot, a dash-dot line marks a Julia patch change.

```bash
git clone --branch bench-data --single-branch \
  https://github.com/yamanori99/DistSSHKit.jl.git kit-bench-data
```

From a package checkout, measure and render without pushing:

```bash
./bench/compile/measure.sh --slot local --history kit-bench-data/history
./bench/compile/render.sh --history kit-bench-data/history
```

`measure.sh` writes a toml under `history/<slot>/`. `render.sh` rewrites
`README.md` and `bench.html` next to that `history` directory. Neither command commits.

## Files

```text
history/<slot>/<YYYY-MM-DD>-<shortsha>.toml
README.md
bench.html
```

`<slot>` is the CI name, such as `1.13`, `1.14-nightly`, or `nightly`. The name
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
`top` (the 20 slowest methods, still used for the flag). Newer Kit samples
also store `methods` (every specialization of this package, plus any other
specialization of at least 200 ms that is not `Main`) and `missed` (source
functions the command did not compile). Older files have only `top`.
DistSSHQueue records `help`, `status`,
`submit`, `watch`, and `cancel`. DistSSHKit records `help`, `status`,
`go`, and `drive`. DistSSHRun records `help`, `go`, and `drive`.

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

`bench.html` draws the method times and every command's wall time.
The charts open on the last 30 days ending at the newest sample.
`+`, `-`, and `?range=` still select the other ranges, including `all`.
Version, host, and Julia changes stay as vertical lines. Each line's
text sits inside the plot, at the top of the line. Labels that would
overlap at the current range drop to the next row. The same events are
listed under each chart, with the time, for the same samples the chart
shows. Hover includes the package version and the host.
A time is a specialization that command compiled. The page shows the
requested count of those times. When the latest sample has fewer than
that count, earlier samples in the window supply the rest. The table
shows that sample's date and the rank the method had there. Its
milliseconds are that measurement, and the millisecond change is the
difference from the sample before it. Above the table, the page shows
the sum of every specialization in that command's trace, and the
difference from the previous sample. It does not
list functions the trace never named. The page is not every method under
`src/`. Each function is one name, so a method that did not compile stays
off the page when another method of that function did. The README keeps
the latest 12 rows and the link to that page.
The public link is GitHub Pages
(`https://yamanori99.github.io/DistSSHKit.jl/bench.html`).
jsDelivr serves `.html` as plain text, so the page is not linked from there.
A method missing from an older `top` list is left out of the line.
It is not drawn as zero, and it is not listed as uncompiled.
