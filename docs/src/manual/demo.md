# [demo](@id Manual-demo)

Install or list the bundled example scripts.

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit demo list
julia --project=. -m DistSSHKit demo install --dest DIR
```

Walkthrough: [First Steps · Demo](@ref Tutorial-Demo).

## Flags / subcommands

| Form | Meaning |
| --- | --- |
| `demo list` | Show demo ids and package paths |
| `demo install` | Copy `demos/with_kit/` and `demos/without_kit/` into `./demos/` |
| `--dest DIR` | Install under `DIR/demos/` instead of `./demos/` |
| `--force` | Overwrite existing demo files |
| `-h` / `--help` | Help |

Layout under `demos/` after install:

| Path | Role | Command |
| --- | --- | --- |
| `with_kit/` | Driver (`init` / `main`) | [`drive`](@ref Manual-drive) or `pipeline!` |
| `without_kit/` | Standalone Julia | `julia …`, [`go`](@ref Manual-go), or `go!` |

Refuses to install into the package's own `demos/` tree. Prefer
`--dest DIR` when developing the kit itself.
