# [Prepare](@id Queue-Tutorial-Prepare)

First-time **queue host** before a [First job](@ref Queue-Tutorial-Client).
Typed path (submit / fetch / teardown): [Walkthrough](@ref Queue-Tutorial-Walkthrough).
This box is always-on **macOS or Linux**. Clients can skip this page if
someone already set that box up.

Also see [Requirements](@ref), [Where files live](@ref Requirements),
[Artifacts and paths](@ref Queue-artifacts),
[User Guide · setup](@ref Queue-setup),
[How it runs](@ref Queue-manual).

`setup` / `serve` / `enable` / `disable` / `add-host` / `remove-host`
refuse `qhost:` — log in to the queue host and run them there.

## Config and inventory

DistSSHKit must be loadable here. `setup` does not install the package and
does not create `~/.distsshqueue/env`. It writes
`~/.distsshqueue/config.toml` if missing. That tree (config / store) is
not the same as `julia --project=`.

Default Julia env (`pkg> add DistSSHKit` there):

```bash
julia -m DistSSHKit qhost setup
julia -m DistSSHKit qhost add-host parent child:host1
julia -m DistSSHKit list-host
julia -m DistSSHKit qhost serve
```

From a checkout of this package, the same verbs with `--project=.`.

Defaults work without `config.toml`. `--force` rewrites it. Use it for
`store=` or `[env]`.

`add-host` writes host tokens into config `hosts`
(`parent[:N]` / `child:NAME[:N]`). `parent` is this queue host;
`child:NAME` is SSH. `add-host child:` warns that submitters as this user
can reach that SSH name, and that the child needs outbound internet for
instantiate unless the depot already has the registry and packages
([Requirements](@ref)). First add creates the
list. CLI submit with a placement token and no `hosts` is an error.
Optional `:N` is a max. No `serve` restart: the next
`submit` re-reads the file. `list-host` NAME for parent is the hostname;
TOKEN stays `parent`. JULIA is that host's `juliaup default` patch
(`1.12.7`; `-` if missing, SSH/`status` fails, or no Version on the `*` row).

Do not `cd` the stage tree and run DistSSHKit `setup` by hand. `serve`
`Pkg.instantiate`s that tree on the queue host, then `setup!`
(`rsync` → `instantiate` → `check`)
on `child:` hosts, unless
`DISTSSHQUEUE_NO_KIT_SETUP=1`. A `qhost:` stage omits `.git/`;
a missing local git commit warns instead of
failing `:check`. Leave
`DISTRIBUTED_REMOTE_PROJECT_ROOT` unset in queue `config.toml` so a
`qhost:` `child:` copy stays `~/stage/<uuid>`. `parent` uses the stage
on the queue host.
[kit Prepare](https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/prepare/).
To align Julia versions, `qhost up` on the machine that stays on
(config `hosts` only; see [Requirements](@ref)).

## Dedicated env (optional)

Create `~/.distsshqueue/env` when clients `qhost:` (`qhost:` defaults to
`--project=~/.distsshqueue/env`) or when `enable` should not pin a
checkout. Skip it if you only `setup` / `add-host` / `serve` from an env
that already has DistSSHKit. `--queue-env @` is the remote default
Julia env (no `--project=`).

```bash
mkdir -p ~/.distsshqueue/env
cd ~/.distsshqueue/env
julia --project=.
```

```julia
pkg> add DistSSHKit
```

That pulls DistSSHQueue and DistSSHRun from General. A different dir is
`--queue-env DIR` on `enable` and on client `qhost:`.

## Survive reboot (optional)

```bash
julia --project=. -m DistSSHKit qhost enable --queue-env ~/.distsshqueue/env
```

`--queue-env` is the env that loads Queue in the OS unit, not Julia
`--project=` / the job project. After that, clients only `submit`. You do
not leave a `serve` terminal open. If there is no dedicated dir,
`enable` uses the Manifest directory of the active project (the workspace
root when this checkout is a member).

Next: [Walkthrough](@ref Queue-Tutorial-Walkthrough), or [First job](@ref Queue-Tutorial-Client).
