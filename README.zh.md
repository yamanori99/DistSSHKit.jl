# DistSSHKit.jl

[English](README.md) | [日本語](README.ja.md) | [简体中文](README.zh.md)

<!-- markdownlint-disable MD013 -->
[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/CI.yml?branch=main&style=flat-square&logo=githubactions&logoColor=white&label=Test)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[![Codecov](https://img.shields.io/codecov/c/github/yamanori99/DistSSHKit.jl?style=flat-square&logo=codecov&logoColor=white)](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[![docs-stable](https://img.shields.io/badge/docs-stable-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[![docs-dev](https://img.shields.io/badge/docs-dev-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
[![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
[![Discussions](https://img.shields.io/badge/GitHub-Discussions-blueviolet?style=flat-square&logo=github)](https://github.com/yamanori99/DistSSHKit.jl/discussions)
<!-- markdownlint-enable MD013 -->

DistSSHKit 是一个通过 SSH 在多台机器上并行 Julia 计算的工具包。
它不仅适用于两台工作站的工作环境，也能支持实验室环境下的多机器计算场景。
现支持 **macOS、Linux 和 WSL2 Ubuntu**（暂不支持原生 Windows）。

安装只需 `pkg> add DistSSHKit`。运行指令是 `julia -m DistSSHKit`。
DistSSHKit 捆绑了 DistSSHRun 和 DistSSHQueue。
因此不需要单独安装它们。

任务可在如下两个场景之一运行。

- **本机。** 在本机启动任务。SSH 连接保持打开，直到任务结束。
  指令是 `go`、`ride`、`drive`、`plan`、
  `size`、`pool`、`demo` 和 `progress`。
- **队列主机。** 一台始终运行的服务器。把任务留在那里。任务一次运行一个。
  需在服务器上安装同一个包。笔记本掉线不会停止已经留在那里的任务。
  指令是 `submit`、`status`、`watch`、`cancel`、`fetch` 和 `serve`。
  本工具使用`qhost` 来指代服务器。

**通道服务器**是两者共用的。`setup` 准备 SSH 主机。`up` 让每台机器使用相同的 Julia 通道。
需要在任一场所开始之前做这件事。

## 安装

在 Julia REPL 中按 `]` 进入 Pkg 模式，然后运行：

```julia
pkg> add DistSSHKit
```

或者使用 `Pkg` API：

```julia
julia> import Pkg; Pkg.add("DistSSHKit")
```

你从其上启动的那台机器还需要 **`ssh`** 和 **`rsync`**，如果使用 git 部署，还需要 **`git`**。
`pkg> add` 不会安装这些。完整的需求列表见
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)。

其余内容见
**[文档](https://yamanori99.github.io/DistSSHKit.jl/stable/)**。

## 使用方法

### 用语解释

- **主机（Host）** — 执行计算的机器。使用 token 指定，
  例如 `parent` 或 `child:user@hostname`。
- **进程（Process）** — 一个正在运行的 `julia` 实例。每个进程有自己的
  内存，并在操作系统层面上独立运行。
  （一次运行会启动多个 `julia` 进程来并行执行
  工作，即使在单台机器上也是如此。它基于 Distributed.jl。）
- **主进程（Master）** — 运行开始所在机器上的进程。使用 `go` 时，
  它规划槽位；使用 `drive` 时，它把工作交给工作进程并
  收集结果。在本机运行 `go` /
  `drive` 时，那台机器就是本机；任务被留在队列服务器上时，那台服务器就是队列主机。
- **工作进程（Worker）** — 从主进程接收工作并执行的进程。

例如，如果你在自己的机器上运行 `go` 或 `drive`，那台机器就是
任务开始的那一侧。每台机器可以运行多个工作进程
（本机可以一个都不运行），
远程机器可以按需要添加任意多台。

<!-- markdownlint-disable MD033 MD013 -->
<p align="center">
  <picture>
    <source
      media="(prefers-color-scheme: dark)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/diagram/topology-dark.svg">
    <source
      media="(prefers-color-scheme: light)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/diagram/topology.svg">
    <img
      alt="Drive 拓扑：主进程与工作进程"
      src="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/diagram/topology.png">
  </picture>
</p>
<!-- markdownlint-enable MD033 MD013 -->

上图表示的是 **drive**：本机上有一个主进程，每台主机上都有工作进程。
**go** 使用相同的主机 token，但没有主进程/工作进程
关系；每台主机各自运行脚本。

```text
parent                 # 本机
parent:2               # 本机上有两个进程
child:user@hostname    # SSH 子机（user@host、IP 或 Host 别名）
child:user@hostname:4  # 该子机上有四个进程
```

SSH 主机的数量没有上限。主机越多，花在
SSH 连接和部署上的时间也越多，所以最好先从几台开始，再逐步增加。

使用 SSH 主机之前，请确认它满足以下条件：

- 可以从运行开始的那台机器通过 SSH 免密码登录。
- 已安装 Julia，并且与那台机器的 **major.minor 版本相同**
  （`setup --check` 会验证这一点）。先用 `up` 把通道对齐。

详情见
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)。

### 本机：go、ride、drive

运行脚本有三种方式：

- **go** — 每台主机全程运行你的 `.jl` 文件。
- **ride** — DistSSHKit 拆分相互独立的 `map`、filter、推导式或
  带下标的 `for` 工作（实验性功能；可在 parent 或 SSH 工作进程上使用）。
- **drive** — 一个主进程把工作分发给各个工作进程（基于 Distributed.jl）。

### 检查：plan（文件）与 pool（主机）

- **plan** — 检查一个 `.jl` 文件，并建议使用 go、ride 或 drive。它只
  从磁盘读取并解析，因此不带 `!`，也不进行 SSH。也可以调用 `size!`
  估算槽位。
- **pool** / **pool!** — 报告所列主机的核心数和内存。它使用
  SSH，因此带 `!`。它不报告 RSS。无法连接的主机仍留在
  列表中，并标记 `ok=false`。

**size** / **size!** 报告占用情况（基于 RSS 的 `WorkerPlan`）。CLI
的 `size` 会打印一份计划。对于 go、drive 和 ride，列出的每个 token 都需要 `:N`
（不给 token 时，会在 parent 上得到一个槽位）。
`go --repeat` 是例外：列出的主机可以省略 `:N`，
这样它们的资源池就没有上限。这些都
不是监控面板，不会持续刷新检测。

单独使用 `go` 已经相当可用。常见流程是先用 `go` 确认一次独立
运行，需要时再转向 `drive` 和 Distributed.jl。
`plan` 后也建议直接使用 `ride`。

### 调用 DistSSHKit 的方式

- **CLI** — 从终端运行 DistSSHKit。
  示例：`julia --project=. -m DistSSHKit go child:user@host1:1 script.jl`。
  适合快速试验和 shell 脚本。
- **Julia** — 从你自己的 Julia 代码（脚本、REPL 或
  另一个包）中调用函数：`setup!`、`go!`、`drive!`、`plan`（不带 `!`）、`pool!`，以及
  其他带 `!` 的函数。

CLI 标志与 Julia API 一一对应。例如，`setup --rsync`
对应 `setup!(session, :rsync)`。
在 `demo install with_kit` 和 `demo install without_kit` 之后，示例见
`distsshkit_demos/with_kit/pipeline_square.jl` 和
`distsshkit_demos/without_kit/pipeline_pi.jl`。

两种方式做的是同一件事，只是调用方式不同。CLI
是最容易上手的地方。

### 准备远程主机

通常在运行脚本之前先运行 `setup`。它部署项目并安装
依赖。每次调用只指定一个部署或初始化操作。远程为空
或不存在时，`go --rsync` 或 `drive --rsync` 可以一步完成项目复制和
实例化（普通的 `go` 和 `drive` 仍然假定远程主机
已经准备好）。

- 首次部署：使用 `--rsync`（按原样发送本地目录树）或
  `--clone`（对仓库执行 `git clone`），不要同时使用两者。
- 依赖：`--instantiate`（在远程运行 `Pkg.instantiate`）。
- 更新（重新部署）：`--sync`（`git push`，然后在每个远程上 `pull`）、
  `--pull`（只 `pull`，不 push），或再次使用 `--rsync`。
- 其他模式：
  - `--check`（验证 SSH、Julia 和依赖）
  - `--cleanup`（结束残留的工作进程）
  - `--prune`（删除 `.distsshkit` 中的 go、drive、setup 和 runs 叶子项；
    已部署的目录树会保留）
  - `--delete`（删除远程项目目录；破坏性操作）

`--rsync`、`--clone`、`--sync`、`--pull`、`up` 和 `up update` 在运行前会
要求确认。传入 `-y` 或 `--yes` 可以非交互运行这些操作，
例如从脚本中运行。`--delete` 和 `--prune`
会要求输入 `delete` 或 `prune`。`-y` 和 `DISTSSHKIT_YES` 仍会跳过该
提示并执行删除。这一跳过行为将在 DistSSHKit 0.11（DistSSHRun 0.2）中停止。
此后保留的方式是传入 `--confirm-path`。
没有 `--confirm-path` 的 `teardown` 会打印 `Would remove`
并且不删除任何内容，除非设置了 `-y` 或 `DISTSSHKIT_YES`。这一跳过
行为将在 DistSSHKit 0.11（DistSSHQueue 0.10）中停止。

详情见
[setup](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/setup/)。

> [!NOTE]
> **不确定用 rsync 还是 git？**
>
> - **`--rsync`** — 直接按原样发送本地文件。远程主机不
>   需要 git。适合第一次尝试或一次性运行。
> - **`--clone` 然后 `--sync`** — 把远程当作 git 仓库来管理。如果会
>   持续更新代码，或者希望
>   `drive --require-git` 确认远程 commit 与本地
>   一致以保证可复现，这种方式更好。

首次设置（rsync 路线）如下：

```bash
# 把文件复制过去
julia --project=. -m DistSSHKit setup --rsync child:user@host1 child:user@host2
# 安装依赖
julia --project=. -m DistSSHKit setup --instantiate child:user@host1 child:user@host2
# 健全性检查
julia --project=. -m DistSSHKit setup --check child:user@host1 child:user@host2
```

其他常用命令：

```bash
# 删除 go/drive/setup/runs 叶子项（保留项目树）
julia --project=. -m DistSSHKit setup --prune child:user@host1 child:user@host2
# 清理残留的工作进程
julia --project=. -m DistSSHKit setup --cleanup child:user@host1 child:user@host2
# 从头重新开始（会要求输入 delete；在 DistSSHKit 0.11 之前，-y 仍会删除）
julia --project=. -m DistSSHKit setup --delete child:user@host1 child:user@host2
```

### 示例

设置完成后，按如下方式运行脚本。

**CLI，go。** 每个槽位会把 `script.jl` 从头到尾运行一次。
`child:user@host:1` 表示在该主机上运行一次，`parent:N` 表示在
本机上运行 N 次。`--repeat N` 表示总共运行 N 次，分摊到列出的
主机上。

```bash
julia --project=. -m DistSSHKit go \
  child:user@host1:1 child:user@host2:1 path/to/script.jl
julia --project=. -m DistSSHKit go --repeat 100 path/to/script.jl
julia --project=. -m DistSSHKit go --repeat 100 \
  child:user@host1 child:user@host2 path/to/script.jl
```

**CLI，drive。** 如果用 git 部署，之后的更新用
`setup --sync` 完成。`rsync` 也可以。

```bash
julia --project=. -m DistSSHKit drive \
  parent:2 child:user@host1:4 path/to/driver.jl
```

**Julia，go。** 让 `remote=` 与 `setup!` 保持一致（两者都省略则使用
默认路径）。

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :rsync, :instantiate)
go!("path/to/script.jl", "child:user@host1:1"; remote=remote)
```

**Julia，drive。**

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :clone; repo="https://github.com/org/proj.git")
setup!(session, :instantiate)
drive!("path/to/driver.jl", "parent:2", "child:user@host1:4"; remote=remote)
setup!(session, :sync)  # 之后的更新
```

`pipeline!` 是一个可选的便利函数，把 sync、`drive!` 和 collect
串成一次调用。它不运行 `setup!`，并且其中的 `sync=:rsync` 只复制文件，
不执行实例化。请事先准备好远程主机，或使用
`drive!(…; sync=:rsync)`。
详情见 [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/)。

### 试用演示

自带的演示可以让你在自己写脚本之前先试用 DistSSHKit。
`with_kit` 演示 drive；`without_kit` 演示独立运行
和 go。

从**任务**项目（已经执行过
`pkg> add DistSSHKit` 的项目）中运行，不要从 DistSSHKit 的检出目录运行：

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo install without_kit
```

```bash
julia --project=. -m DistSSHKit drive parent:2 distsshkit_demos/with_kit/square_file.jl
julia --project=. -m DistSSHKit go parent:2 distsshkit_demos/without_kit/pi_file.jl
```

逐步说明见
[Demo](https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/demo/)。

### 队列主机

```text
  client (dev machine, no cap)            queue host (always on, log in here)
  ----------------------------            ------------------------------------
  yours / a colleague's                   FIFO     one job at a time
       |                                  table    ~/.distsshqueue
       |  julia --project=.               julia -m DistSSHKit
       |    -m DistSSHKit                  qhost setup / add-host
       |    qhost:HOST submit              qhost serve
       |    status | fetch | cancel        qhost enable  after reboot
       +--------------------------------> then go / ride / drive
                                          -> workers (parent / child:)
```

**队列主机。** 登录那台始终开着的 macOS 或 Linux 机器，并用
`pkg> add DistSSHKit` 在那里安装同一个包。在队列主机上运行的每条命令
都需以 `qhost` 开头，如若使用`qhost:HOST` 这种 token 会被拒绝。
请使用默认的 Julia 环境，所以无需传递 `--project=.`：

```bash
julia -m DistSSHKit qhost setup
julia -m DistSSHKit qhost add-host parent child:host1
julia -m DistSSHKit qhost serve
```

`qhost enable` 会让 `serve` 在重启后再次启动。

**客户端。** 留在存放任务的那台机器上。`qhost:HOST` 是队列主机的 SSH 名称，
把它放在 `submit`、`status`、`fetch` 和 `cancel` 前面。
该连接使用队列主机上的 `~/.distsshqueue/env`。如何
创建该环境，见 [Prepare][q-prepare]。

```bash
julia --project=. -m DistSSHKit qhost:HOST submit go parent:1 distsshkit_demos/without_kit/pi_echo.jl
```

详情见 [Prepare][q-prepare]、[Walkthrough][q-walk] 和
[How it runs][q-manual]。

## 文档

官方文档正文是英文。页面名称也保持英文。

- [Home][home]
- First Steps
  - [Requirements][req]
  - This machine
    - [Prepare][t-prepare]
    - [Demo][t-demo]
  - Always-on machine
    - [Prepare the machine][q-prepare]
    - [First job][q-client]
    - [Walkthrough][q-walk]
- User Guide
  - [Overview][manual]
  - Prepare hosts
    - [setup][m-setup]
    - [up][m-up]
  - This machine
    - [go][m-go]
    - [ride][m-ride]
    - [drive][m-drive]
    - [plan][m-plan]
    - [size][m-size]
    - [pool][m-pool]
    - [paths][m-paths]
    - [demo][m-demo]
  - Always-on machine
    - [How it runs][q-manual]
    - [Artifacts and paths][q-artifacts]
    - [submit][q-submit]
    - [status][q-status]
    - [fetch][q-fetch]
    - [hosts][q-hosts]
    - [serve][q-serve]
    - [qhost setup][q-setup]
- [API][api]
- 更新记录：[NEWS.md](NEWS.md)。至 0.9.0：[HISTORY.md](HISTORY.md)。

## 包

- [DistSSHKit][home] `ceec0504-c968-4be5-b215-667cae0e8f81`
- [DistSSHRun][run] `b568025c-2759-4ef1-8b14-17d00e2cd000`
- [DistSSHQueue][queue] `24254401-70d8-4a51-8ea4-cfab19f5bc73`

## 贡献

在
[Issues](https://github.com/yamanori99/DistSSHKit.jl/issues)
中报告 bug 和提出功能请求。
在
[Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions)
中提问和分享想法。
贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

源代码以 [MIT](LICENSE) 许可证发布。项目标志和示意图中的 Julia 圆点
版权为 Copyright (c) 2012-2022 Stefan Karpinski，
许可协议为
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)。
DistSSHKit 使用了它们的改编版本。详情见
[LICENSE](LICENSE) 和
[julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics)。

<!-- markdownlint-disable MD013 -->
[home]: https://yamanori99.github.io/DistSSHKit.jl/stable/
[req]: https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/
[t-prepare]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/prepare/
[t-demo]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/demo/
[q-prepare]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/queue-prepare/
[q-client]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/queue-client/
[q-walk]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/queue-walkthrough/
[manual]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/
[m-setup]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/setup/
[m-up]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/up/
[m-go]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/go/
[m-ride]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/ride/
[m-drive]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/drive/
[m-plan]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/plan/
[m-size]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/size/
[m-pool]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/pool/
[m-paths]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/paths/
[m-demo]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/demo/
[q-manual]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/
[q-artifacts]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/artifacts/
[q-submit]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/submit/
[q-status]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/status/
[q-fetch]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/fetch/
[q-hosts]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/hosts/
[q-serve]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/serve/
[q-setup]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/setup/
[api]: https://yamanori99.github.io/DistSSHKit.jl/stable/api/
[run]: https://yamanori99.github.io/DistSSHRun.jl/stable/
[queue]: https://yamanori99.github.io/DistSSHQueue.jl/stable/
<!-- markdownlint-enable MD013 -->

<!-- markdownlint-disable MD033 MD013 -->
<p align="center">
  <picture>
    <source
      media="(prefers-color-scheme: dark)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/logo/logo-dark-static.svg">
    <source
      media="(prefers-color-scheme: light)"
      srcset="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/logo/logo-static.svg">
    <img
      src="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/logo/logo-static.png"
      width="180"
      alt="DistSSHKit.jl 标志"/>
  </picture>
</p>
<!-- markdownlint-enable MD033 MD013 -->
