# [Package split](@id Developers-package-split)

Most users install **DistSSHKit** and use `julia -m DistSSHKit` only. This table is for **embedding** or **queue-only** installs.

| Goal | Package | How you run it | Docs |
| --- | --- | --- | --- |
| Default install, notebooks, mixed local + queue client | **DistSSHKit** | `julia -m DistSSHKit` or `using DistSSHKit` | This site: [Requirements](@ref), [User Guide](@ref Manual), [API](@ref API) |
| Run scripts on SSH hosts without queue features | **DistSSHRun** | `julia -m DistSSHRun` or `using DistSSHRun` | Kit manual for commands ([setup](@ref Manual-setup), [go](@ref Manual-go), …); [DistSSHRun API](https://yamanori99.github.io/DistSSHRun.jl/stable/) |
| Queue host or queue-only embedding | **DistSSHQueue** | `julia -m DistSSHQueue` or `using DistSSHQueue` | [How it runs](@ref Queue-manual), [First job](@ref Queue-Tutorial-Client); [DistSSHQueue API](https://yamanori99.github.io/DistSSHQueue.jl/stable/) |
| Host tokens, deploy, Julia channel sync | **DistSSHRun.DistSSHBase**, **DistSSHRun.DistSSHUp** | Submodules of DistSSHRun | [setup](@ref Manual-setup), [up](@ref Manual-up), [API](@ref API) |