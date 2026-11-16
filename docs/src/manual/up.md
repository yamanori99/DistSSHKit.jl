# [up](@id Manual-up)

Put the same Julia channel on each machine before
[`go`](@ref Manual-go) / [`drive`](@ref Manual-drive), or before you leave
a job on a queue host.

```bash
julia --project=. -m DistSSHKit up user@host
julia --project=. -m DistSSHKit up parent
julia --project=. -m DistSSHKit up update user@host
```

`up user@host` and `up parent` run `juliaup add`, `juliaup update`, and
`juliaup default` for this machine's major.minor channel. `up update`
runs `juliaup update` and leaves the default channel alone.

`parent` is the head row label here ([`is_parent_host_name`](@ref)). [`setup`](@ref Manual-setup) takes
bare SSH host names only. `N*host` counts are stripped when present.

The setup parser still accepts `--juliaup` and `--juliaup-update`. Those
flags do the same work and tell you to use `up` / `up update` instead.

On a queue host the same verbs are `qhost up` and
`qhost up update` ([setup](@ref Queue-setup)).

Also: [Requirements](@ref), `help up`.
