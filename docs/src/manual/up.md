# [Julia version](@id Manual-up)

Put the same Julia channel on each machine before
[`go`](@ref Manual-go) / [`drive`](@ref Manual-drive), or before you leave
a job on an always-on machine.

```bash
julia --project=. -m DistSSHKit up child:NAME
julia --project=. -m DistSSHKit up parent
julia --project=. -m DistSSHKit up update child:NAME
```

`up child:NAME` and `up parent` run `juliaup add`, `juliaup update`, and
`juliaup default` for this machine's major.minor channel. `up update`
runs `juliaup update` and leaves the default channel alone.

`parent` / `parent:N` belong here. [`setup`](@ref Manual-setup) takes
`child:NAME` only. `:N` is ignored.

The setup parser still accepts `--juliaup` and `--juliaup-update`. Those
flags do the same work and tell you to use `up` / `up update` instead.

On an always-on machine the same verbs are `qhost up` and
`qhost up update` ([setup](@ref Queue-setup)).

Also: [Requirements](@ref), `up --help`.
