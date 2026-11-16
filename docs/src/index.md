```@raw html
---
layout: home

hero:
  name: Multi-machine Julia over SSH
  text: DistSSHKit
  tagline: "Run Julia on SSH machines from your laptop, including Distributed drive workers. Or submit to a queue on an always-on host and fetch results after you disconnect."
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
  - title: Run from this machine
    link: manual/go/
    details: Start go or drive from your laptop; SSH stays up until the run finishes and workers join over the network.
  - title: Prepare SSH hosts
    link: tutorial/prepare/
    details: Deploy your project to each machine and match Julia channels before you run or queue.
  - title: Queue on an always-on host
    link: tutorial/queue-client/
    details: Submit from your laptop; jobs run on the queue host one at a time while you disconnect and collect results later.
---
```

## [Install](@id Home)

Julia **1.13+** on **macOS, Linux, and WSL2 Ubuntu** (not native Windows).

```julia
pkg> add DistSSHKit
```

You still need **`ssh`**, **`rsync`**, and **`git`** (git deploy only) on the machines involved. See [Requirements](@ref).

## What you can do

One **`julia -m DistSSHKit`** install covers host prep, runs you start on **this machine**, and client commands that talk to a **queue host**.

**Run (interactive).** From your laptop or login node, [`go`](@ref Manual-go) runs a script on listed SSH slots; [`drive`](@ref Manual-drive) keeps a master process here and adds Distributed workers on parent and remote hosts while you stay connected. See [User Guide](@ref Manual) for [`ride`](@ref Manual-ride), [`pool`](@ref Manual-pool), and the rest.

**Queue (away from keyboard).** On a machine that stays powered on, [`qhost setup`](@ref Queue-setup) turns it into a queue that accepts jobs. From your job project on the laptop you `submit`, check `status`, and `fetch` output when you are back ([First job](@ref Queue-Tutorial-Client), [How it runs](@ref Queue-manual)).

Host prep is shared: run [`setup`](@ref Manual-setup) and [`up`](@ref Manual-up) once per cluster before either style.

## How it works

1. **Prepare hosts.** [`setup`](@ref Manual-setup) and [`up`](@ref Manual-up) put your project and the same Julia channel on each SSH machine ([Prepare](@ref Tutorial-Prepare)).
2. **Run now (optional).** While connected, start a run from this machine—for example `julia -m DistSSHKit go host SCRIPT.jl` or a [`drive`](@ref Manual-drive) script with workers ([`go`](@ref Manual-go)).
3. **Or use the queue.** On the always-on host, run [`qhost setup`](@ref Queue-setup) ([Prepare the machine](@ref Queue-Tutorial-Prepare)). From the laptop, submit the same kinds of jobs (`go`, `ride`, `drive`) to that host; they execute there after you disconnect.

Example **run from this machine**:

```bash
julia --project=. -m DistSSHKit go --head-slots 1 2*user@host SCRIPT.jl
```

Example **queue client** from a job project:

```bash
julia --project=. -m DistSSHKit qhost:HOST submit go --head-slots 1 SCRIPT.jl
julia --project=. -m DistSSHKit qhost:HOST status
julia --project=. -m DistSSHKit qhost:HOST fetch <id>
```

Embedders who install [DistSSHRun](https://yamanori99.github.io/DistSSHRun.jl/stable/) or [DistSSHQueue](https://yamanori99.github.io/DistSSHQueue.jl/stable/) without Kit: [Package split](@ref Developers-package-split).

Questions: [Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions). License: [MIT](https://github.com/yamanori99/DistSSHKit.jl/blob/main/LICENSE).