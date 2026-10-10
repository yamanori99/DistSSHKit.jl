# [Walkthrough](@id Queue-Tutorial-Walkthrough)

Commands in the order you type them. Flags and trees stay on
[Prepare](@ref Queue-Tutorial-Prepare), [First job](@ref Queue-Tutorial-Client),
the [User Guide](@ref Queue-manual), and
[Artifacts and paths](@ref Queue-artifacts). Not a dump of root `--help`.

Names here: queue host SSH `HOST`, worker SSH `host1`. Swap them.

## Queue host (once)

Always-on **macOS or Linux**. Default Julia env is enough
(`pkg> add DistSSHKit` there). `setup` writes `config.toml` only.
`parent` is this box. Dedicated `~/.distsshqueue/env` is optional
until a client uses `qhost:` (`qhost:` defaults to
`--project=~/.distsshqueue/env`).

```bash
julia -m DistSSHKit qhost setup
julia -m DistSSHKit qhost add-host parent child:host1
julia -m DistSSHKit qhost size
julia -m DistSSHKit qhost serve
```

`add-host` does not deploy. `serve` instantiates the job project on
this host, then `setup!` (rsync / instantiate / `check`) on
`child:` hosts. A `qhost:` stage has no `.git/`; a missing local git
commit warns instead of failing `:check`. Optional: `qhost up`
when major.minor differs.

From a client: create the env, then `pkg> add DistSSHKit` in it
(Prepare). `enable` is optional (survive reboot). Every client verb
needs `qhost:HOST` on the command line.

## Client: go on parent

Job directory. DistSSHKit in this project (`julia --project=.`) brings
the queue. `demo install` copies into `distsshkit_demos/`.
Listed `parent` / `child:NAME` need `:N`.

```bash
julia --project=. -m DistSSHKit demo install without_kit
julia --project=. -m DistSSHKit qhost:HOST submit go parent:1 distsshkit_demos/without_kit/pi_echo.jl
```

`qhost:` rsyncs this tree to `~/.distsshqueue/stage/<uuid>` on `HOST`
(excludes `.gitignore`, `.git/`, `.distsshkit/`, `.distsshqueue/`). Stdout is the job UUID. This client has
`.distsshqueue/tickets/<uuid>` only; the result leaf is not here yet.

```bash
julia --project=. -m DistSSHKit qhost:HOST status
julia --project=. -m DistSSHKit qhost:HOST fetch <id>  # 8-char prefix or full UUID
julia --project=. -m DistSSHKit qhost:HOST fetch .distsshqueue/tickets/<uuid>
```

`fetch` copies the result leaf onto
`{project}/.distsshqueue/go/<stem>_<id8>/` on this job tree (on `HOST`,
the job writes under the stage tree's `.distsshkit/`). Run it from the
same directory as `submit`.

## Worker (`child:NAME`)

From the **client**:

```bash
julia --project=. -m DistSSHKit qhost:HOST submit go child:host1:2 distsshkit_demos/without_kit/pi_echo.jl
julia --project=. -m DistSSHKit qhost:HOST fetch <id>
```

Or the same `:N` on every config host:

```bash
julia --project=. -m DistSSHKit qhost:HOST submit pool:2 go distsshkit_demos/without_kit/pi_echo.jl
```

## Drive

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit qhost:HOST submit drive parent:1 distsshkit_demos/with_kit/square_file.jl
julia --project=. -m DistSSHKit qhost:HOST fetch <id>
```

## Teardown (queue host)

```bash
julia -m DistSSHKit teardown -y
```
