# [demo](@id Manual-demo)

Install or list the bundled example scripts.

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo list
julia --project=. -m DistSSHKit demo install without_kit --dest DIR
```

Examples: [First Steps · Demo](@ref Tutorial-Demo).

## Flags / subcommands

- `demo list`: show demo ids and package paths
- `demo install with_kit`: copy package `demos/with_kit/` into
  `./distsshkit_demos/`
- `demo install without_kit`: copy package `demos/without_kit/` into
  `./distsshkit_demos/`
- `--dest DIR`: install under `DIR/distsshkit_demos/` instead of
  `./distsshkit_demos/`
- `--force`: overwrite existing demo files
- `-h` / `--help`: help

Bare `demo install` (both families) is refused. Layout under
`distsshkit_demos/` after install:

- `with_kit/`: driver (`init` / `main`). [`drive`](@ref Manual-drive) or
  `pipeline!`
- `without_kit/`: standalone Julia. `julia …`, [`go`](@ref Manual-go), or
  `go!`

The package tree stays `demos/with_kit/` and `demos/without_kit/`. Install
does not use `.distsshkit/` (rsync excludes it).

Refuses `dest` equal to the DistSSHKit package root. Prefer `--dest DIR`
when developing the kit itself.
