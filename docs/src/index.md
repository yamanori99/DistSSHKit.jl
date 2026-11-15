```@raw html
---
layout: home

hero:
  name: Multi-machine Julia over SSH
  text: DistSSHKit
  tagline: "Install DistSSHKit on an always-on machine to get your own personal Julia cluster. The queue runs jobs while your laptop is away."
  actions:
    - theme: brand
      text: Requirements
      link: requirements/
    - theme: brand
      text: First queue job
      link: tutorial/queue-client/
    - theme: alt
      text: User Guide
      link: manual/
  image:
    src: /logo/logo-dynamic.svg
    dark: /logo/logo-dark-dynamic.svg
    alt: "DistSSHKit.jl logo"

features:
  - title: Your personal cluster
    link: tutorial/queue-client/
    details: Leave work on an always-on queue host; jobs run one at a time while you disconnect and fetch results later.
  - title: Prepare SSH hosts
    link: tutorial/prepare/
    details: Deploy your project to the machines that will run jobs, then verify SSH and Julia match.
  - title: Run from this machine
    link: manual/go/
    details: When you stay connected, run the same scripts directly over SSH without using the queue.
---
```

## [Install](@id Home)

Julia **1.13+** on **macOS, Linux, and WSL2 Ubuntu** (not native Windows).

```julia
pkg> add DistSSHKit
```

You still need **`ssh`**, **`rsync`**, and **`git`** (git deploy only) on the machines involved. See [Requirements](@ref).

## How it works

1. **Prepare hosts.** [`setup`](@ref Manual-setup) and [`up`](@ref Manual-up) put your project and the same Julia channel on each SSH machine ([Prepare](@ref Tutorial-Prepare)).
2. **Start the queue.** On your always-on machine, run [`qhost setup`](@ref Queue-setup) so it can accept jobs ([Prepare the machine](@ref Queue-Tutorial-Prepare)).
3. **Submit from your laptop.** From your job directory, use `submit`, then `status` and `fetch` when you are back ([First job](@ref Queue-Tutorial-Client)).

Most day-to-day use is steps 2 and 3. The queue is the engine. Prepare hosts, and optional `go` or `drive` on this machine, are there when you need them ([User Guide](@ref Manual)).

Typical client flow from a job project:

```bash
julia --project=. -m DistSSHKit qhost:HOST submit go parent:1 SCRIPT.jl
julia --project=. -m DistSSHKit qhost:HOST status
julia --project=. -m DistSSHKit qhost:HOST fetch <id>
```

Embedders who install [DistSSHRun](https://yamanori99.github.io/DistSSHRun.jl/stable/) or [DistSSHQueue](https://yamanori99.github.io/DistSSHQueue.jl/stable/) without Kit: [Package split](@ref Developers-package-split).

Questions: [Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions). License: [MIT](https://github.com/yamanori99/DistSSHKit.jl/blob/main/LICENSE).