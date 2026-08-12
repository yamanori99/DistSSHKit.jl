# DistSSHKit.jl

[CI](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[codecov](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[Aqua QA](https://github.com/JuliaTesting/Aqua.jl)

[Stable](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[Dev](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[Julia 1.12+](https://julialang.org/)
[License: MIT](LICENSE)

DistSSHKit makes it easy to run one Julia project locally and over SSH, then
collect the results. It uses Distributed.jl processes (not threads). **macOS
and Linux.**

These days, even small labs and individuals often have several high-performance
machines or workstations. DistSSHKit helps you put that hardware to work.

> [!IMPORTANT]
> **Under active development.** Prefer a release tag for `rev`. Use `rev="main"` only for the development tip.

## Install

In your project (`Project.toml` at the project root):

```bash
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/yamanori99/DistSSHKit.jl.git", rev="v0.2.0")'
```

For the development tip, use `rev="main"` instead.

Install, demo, `go` / `drive`, remote hosts, and API: **[Documentation](https://yamanori99.github.io/DistSSHKit.jl/stable/)**.

## Documentation


|              |                                                                                |
| ------------ | ------------------------------------------------------------------------------ |
| Introduction | [Introduction](https://yamanori99.github.io/DistSSHKit.jl/stable/)             |
| First Steps  | [First Steps](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/) |
| User Guide   | [User Guide](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/)        |
| API          | [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/)                  |


## Contributing

Bugs and features to track: [Issues](https://github.com/yamanori99/DistSSHKit.jl/issues).
Questions, ideas, and other chat: [Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions).
See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute.



