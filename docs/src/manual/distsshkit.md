# [distsshkit](@id Manual-distsshkit)

A third way to call the kit: a `distsshkit` command in the terminal, like
`git` or `rsync`. Same flags as `julia -m DistSSHKit`.

!!! warning "Experimental · Julia 1.12+"
    This is [Pkg Apps](https://pkgdocs.julialang.org/v1/apps/). The default
    remains `pkg> add` and `julia --project=. -m DistSSHKit`.

```julia
pkg> app add DistSSHKit
```

Add `~/.julia/bin` to `PATH` if Pkg asks. Same argv, different kit:

```bash
distsshkit go child:user@host:1 path/to/script.jl
julia --project=. -m DistSSHKit go child:user@host:1 path/to/script.jl
```

The first always runs the Apps copy of DistSSHKit, not the kit in
`--project=.`.

| Command | Use |
| --- | --- |
| `go` / `setup` / `demo` | `distsshkit …` |
| `drive` / `size` | `julia --project=. -m DistSSHKit …` |

```bash
distsshkit demo install with_kit
distsshkit setup --rsync user@host1
distsshkit setup --instantiate user@host1
# or one-shot onto an empty path (instantiates if needed):
# distsshkit go --rsync child:user@host1:1 path/to/script.jl
# size / drive: job project, not the Apps copy
julia --project=. -m DistSSHKit size parent child:user@host1
distsshkit go child:user@host1:1 path/to/script.jl
```

`drive` / `size` stay on `-m` because Apps pins `JULIA_LOAD_PATH`.

After you change the Julia / juliaup channel that Apps pins: `pkg> app update DistSSHKit`.
Flag lists: `distsshkit {cmd} --help` or the [command pages](@ref Manual).
