# DistSSHKit.jl

[![CI](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/yamanori99/DistSSHKit.jl/graph/badge.svg?token=6OT4L5JDUW)](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

DistSSHKit makes it easy to run your Julia project locally and over SSH, then
collect the results. Distributed.jl processes (not threads). **macOS and Linux.**

> [!IMPORTANT]
> **Under active development.** Prefer a release tag for `rev`. Use `rev="main"` only for the development tip.

## Install

In your project (`Project.toml` at the project root):

```bash
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/yamanori99/DistSSHKit.jl.git", rev="v0.1.0")'
```

For the development tip, use `rev="main"` instead.

Install, demo, `go` / `drive`, remote hosts, and API: **[Documentation](https://yamanori99.github.io/DistSSHKit.jl/stable/)**.

## Links

| | |
| --- | --- |
| Introduction | [Introduction](https://yamanori99.github.io/DistSSHKit.jl/stable/) |
| First Steps | [First Steps](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/) |
| User Guide | [User Guide](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/) |
| API | [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="docs/src/assets/logo-static.svg" width="180" alt="DistSSHKit.jl logo"/>
</p>
<!-- markdownlint-enable MD033 -->
