# [Prepare](@id Tutorial-Prepare)

First-time remotes before the [Demo](@ref Tutorial-Demo).
Local-only demos can skip this page.

Also see [Requirements](@ref), [User Guide · setup](@ref Manual-setup),
[Introduction](@ref DistSSHKit.jl).

## [First-time remotes](@id first-time-remotes)

Every machine that runs jobs needs the project **and** its dependencies.
Deploy the tree, then **instantiate on each remote** before `go` / `drive`:

```bash
# Local (once): deps for this project
julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Remotes: copy the tree, then install deps from Manifest.toml
julia --project=. -m DistSSHKit setup --rsync YourHost1 YourHost2
julia --project=. -m DistSSHKit setup --instantiate YourHost1 YourHost2
```

Git deploy uses `--clone` instead of `--rsync`, then the same `--instantiate`.
Skipping instantiate is a common cause of remote failures such as
`failed to find source of parent package: "…"`.
`go` / `drive` and `setup --check` probe remotes first and fail fast with an
`--instantiate` hint when deps are missing.

Same steps from Julia:

```julia
session = KitSession(workers=["YourHost1", "YourHost2"], remote="/path/to/project")
sync!(session; mode=:rsync)
instantiate!(session)
```

After rsync (no remote `.git/`), just run `go` / `drive` — neither pre-runs
sync nor requires git parity by default. Optional: `go --sync` / `drive --sync`
/ `drive --rsync` for a one-shot deploy, or `drive --require-git` on
git-managed remotes. Kit logs for setup land under
`<project>/.distsshkit/setup/`.

Verify when ready:

```bash
julia --project=. -m DistSSHKit setup --check YourHost1 YourHost2
```

Clean slate (confirm when prompted):

```bash
julia --project=. -m DistSSHKit setup --delete YourHost1 YourHost2
```

Next: [Demo](@ref Tutorial-Demo).
