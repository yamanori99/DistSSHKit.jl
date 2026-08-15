# [distsshkit](@id Manual-distsshkit)

A third way to call the kit: a `distsshkit` command in the terminal, like
`git` or `rsync`. Same flags as `julia -m DistSSHKit`. Julia **1.12+**
([Pkg Apps](https://pkgdocs.julialang.org/v1/apps/), experimental). Default
remains `pkg> add` and `julia --project=. -m DistSSHKit`.

```julia
pkg> app add DistSSHKit
```

Add `~/.julia/bin` to `PATH` if Pkg asks. Then `distsshkit go …` matches
`julia -m DistSSHKit go …`, but it always runs the Apps copy of DistSSHKit,
not the kit in `--project=.`.

| Command | Use |
| --- | --- |
| `go` / `setup` / `demo` | `distsshkit …` is fine |
| `drive` / `size` | stay on `julia --project=. -m DistSSHKit …` (Apps pins `JULIA_LOAD_PATH`) |

After changing juliaup: `pkg> app update DistSSHKit`. Flag lists:
`distsshkit {cmd} --help` or the [command pages](@ref Manual).
