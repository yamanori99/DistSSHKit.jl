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

# Remotes: deploy the tree, then install deps from Manifest.toml
# Pick one first deploy (rsync: no remote .git/):
julia --project=. -m DistSSHKit setup --rsync YourHost1 YourHost2
# or: julia --project=. -m DistSSHKit setup --clone YourHost1 YourHost2
julia --project=. -m DistSSHKit setup --instantiate YourHost1 YourHost2
# optional: job Pkg.test() on remotes (not DistSSHKit's tests)
# julia --project=. -m DistSSHKit setup --runtest YourHost1 YourHost2
```

`--rsync` is the usual first deploy; `--clone` is the git path (later updates:
`setup --sync`). After `setup --rsync` or `--clone`, run `--instantiate`.
Not sure which to pick? See
[setup · rsync or git?](@ref Manual-setup-rsync-or-git).
Skipping instantiate is a common cause of remote failures such as
`failed to find source of parent package: "…"`.
Default `go` / `drive` and `setup --check` probe remotes first and fail fast
with an `--instantiate` hint when deps are missing. `go --rsync` /
`drive --rsync` copy first, instantiate if Manifest deps are still missing,
then check — only onto a missing/empty remote path (or `setup --delete` first).

Same steps from Julia:

```julia
session = KitSession(workers=["child:YourHost1", "child:YourHost2"], yes=true)
setup!(session, :rsync, :instantiate)
# optional: setup!(session, :check); setup!(session, :juliaup); setup!(session, :runtest)
# git remotes: setup!(session, :clone; repo="https://…") then :instantiate
# later updates: setup!(session, :sync)
```

CLI and API share the default remote root (`~/Parent/RepoName`). If you override
it (`setup --remote-path` / `KitSession(; remote=…)`), pass the same path to
`go` / `drive` / `go!` / `drive!` / `pipeline!`.

After setup, just run `go` / `drive` — neither pre-runs sync nor requires git
parity by default. Optional one-shot onto an empty/missing remote:
`go --rsync` / `drive --rsync` (instantiates if needed). Later git updates
(`go --sync` / `drive --sync`) need a `--clone` / git-managed remote, not an
rsync tree. Commit parity is drive-only:
`drive --require-git` on git-managed remotes. Kit logs for setup land under
`{project}/.distsshkit/setup/`. Put `.distsshkit/` in the job `.gitignore`
([User Guide](@ref Manual)).

Verify when ready:

```bash
julia --project=. -m DistSSHKit setup --check YourHost1 YourHost2
```

If check fails on Julia major.minor (and hosts already have juliaup):

```bash
julia --project=. -m DistSSHKit setup --juliaup YourHost1 YourHost2
```

Clean slate (confirm when prompted):

```bash
julia --project=. -m DistSSHKit setup --delete YourHost1 YourHost2
```

Next: [Demo](@ref Tutorial-Demo).
