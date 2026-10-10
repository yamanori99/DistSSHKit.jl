# DistSSHKit.jl

[English](README.md) · [日本語](README.ja.md)

<!-- markdownlint-disable MD013 -->
[![Test](https://img.shields.io/github/actions/workflow/status/yamanori99/DistSSHKit.jl/CI.yml?branch=main&style=flat-square&logo=githubactions&logoColor=white&label=Test)](https://github.com/yamanori99/DistSSHKit.jl/actions/workflows/CI.yml)
[![PkgEval](https://juliaci.github.io/NanosoldierReports/pkgeval_badges/D/DistSSHKit.square.svg)](https://juliaci.github.io/NanosoldierReports/pkgeval_badges/D/DistSSHKit.html)
[![Codecov](https://img.shields.io/codecov/c/github/yamanori99/DistSSHKit.jl?style=flat-square&logo=codecov&logoColor=white)](https://codecov.io/gh/yamanori99/DistSSHKit.jl)
[![docs-stable](https://img.shields.io/badge/docs-stable-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/)
[![docs-dev](https://img.shields.io/badge/docs-dev-blue?style=flat-square&logo=gitbook&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/dev/)
[![Julia 1.13+](https://img.shields.io/badge/Julia-1.13+-9558B2?style=flat-square&logo=julia&logoColor=white)](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
[![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
[![Discussions](https://img.shields.io/badge/GitHub-Discussions-blueviolet?style=flat-square&logo=github)](https://github.com/yamanori99/DistSSHKit.jl/discussions)
<!-- markdownlint-enable MD013 -->

追加するパッケージは DistSSHKit である。Julia のプロジェクトを、共有マシンへ SSH して、今すぐかあとで実行する。
対応環境は **macOS、Linux、WSL2 Ubuntu** である (ネイティブ Windows は対象外)。

小規模な研究室や個人でも、高性能なマシンやワークステーションを複数台所有していることは少なくない。
DistSSHKit は、それらを束ねて小さな計算ノード群として活用するためのものである。

必要な操作は `pkg> add DistSSHKit` のみである。
ジョブの即時実行にも、キューによる実行にも、このパッケージだけで対応できる。
DistSSHKit は次の2つの仕組みから成り、コマンドは `julia -m DistSSHKit` で呼び出す。

- **[DistSSHRun](https://yamanori99.github.io/DistSSHRun.jl/stable/)**
  は、起動したマシンからジョブを即座に実行する。
  ジョブが終了するまで SSH 接続は維持される。
  コマンドは `setup`、`up`、`go`、`ride`、`drive`、`plan`、`size`、
  `pool`、`demo`、`progress` である。
  `tmux` によるセッションの維持にも対応し、接続自体も維持される。
- **[DistSSHQueue](https://yamanori99.github.io/DistSSHQueue.jl/stable/)**
  は、常時稼働しているマシンにジョブを蓄積し、順番に実行する。
  このマシンにも同じパッケージを導入する。
  手元の接続が切れても、キューに投入済みのジョブは停止しない。

## インストール

Julia の REPL で `]` を押して Pkg モードに入り、次のコマンドを実行する。

```julia
pkg> add DistSSHKit
```

`Pkg` API を用いる場合は次のように書く。

```julia
julia> import Pkg; Pkg.add("DistSSHKit")
```

DistSSHKit を実行するマシンには、**`ssh`** と **`rsync`** が必要である。
git によるデプロイを使う場合は、さらに **`git`** も必要となる。
これらは `pkg> add` では導入されない。動作要件の詳細は
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
を参照されたい。

パッケージの詳細は
**[ドキュメント](https://yamanori99.github.io/DistSSHKit.jl/stable/)**
にまとめている。

## 使用方法

### 基本用語

- **ホスト** — 計算を行うマシン。`parent` や `child:user@hostname` のようなトークンで指定する。
- **プロセス** — 起動された `julia` の1つ分の実体。それぞれが独立したメモリを持ち、OS 上で別々に動作する。
  (本キットは1台のマシン上でも複数の `julia` プロセスを起動し、並列に実行する。基盤は Distributed.jl である)
- **マスター** — キット起動側のプロセス。`go` ではスロットの割り当てを計画し、`drive` ではワーカーに処理を割り振って結果を回収する。
  キット起動側とは、そのプロセスを起動したマシンを指す。
- **ワーカー** — マスターから処理を受け取って実行するプロセス。

例えば手元で `go` や `drive` を実行した場合、そのマシンがキット起動側となる。
ワーカーは1台のマシンに複数起動できる (キット起動側のワーカー数は0でもよい)。リモートマシンも台数に制限なく追加できる。

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
      alt="Drive topology: master and workers"
      src="https://raw.githubusercontent.com/yamanori99/DistSSHKit.jl/main/docs/src/assets/diagram/topology.png">
  </picture>
</p>
<!-- markdownlint-enable MD033 MD013 -->

上図は **drive** の構成である。キット起動側に1つのマスターがあり、各ホストにワーカーが配置される。
**go** でもホストの指定方法は同じだが、マスターとワーカーの関係はなく、各ホストが独立してスクリプトを実行する。

```text
parent                 # キット起動側
parent:2               # キット起動側でワーカーを2つ起動
child:user@hostname    # SSH 先 (user@host / IP / Host エイリアス)
child:user@hostname:4  # SSH 先でワーカーを4つ起動
```

SSH 先の台数に上限はない。ただし、台数が増えるほど SSH 接続や配置に要する時間も長くなるため、まずは数台から試すとよい。

利用にあたっては、各 SSH 先が次の条件を満たしている必要がある。

- キット起動側からパスワードなしで SSH ログインできること
- Julia がインストールされており、キット起動側と **メジャー.マイナーバージョンが一致**していること
  (`setup --check` で確認できる)

詳細は
[Requirements](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
を参照されたい。

### 即時実行: go、ride、drive

実行方式は次の3種類である。

- **go** — 各ホストが、指定された `.jl` ファイルをそのまま最初から最後まで実行する
- **ride** — キットが、互いに独立な `map`、filter、内包表記、添字 `for` を分割して実行する
  (実験的機能。parent または SSH 先で利用可能)
- **drive** — 1つのマスターがワーカーに処理を割り振る (Distributed.jl ベース)

### 事前確認: plan (ファイル) と pool (ホスト)

- **plan** — `.jl` ファイルを検査し、go、ride、drive のうち適切な方式を提案する。
  処理はディスクの読み込みと構文解析のみで、bang 付きではなく SSH も行わない。
  スロット数の見積もりが必要な場合は `size!` を呼び出す
- **pool** / **pool!** — 指定したホストのコア数と RAM を取得する。
  SSH を用いるため bang 付きである。RSS は取得しない。
  接続できないホストは `ok=false` のまま残る

**size** / **size!** は占有状況 (RSS に基づく WorkerPlan) を扱う。
CLI の `size` で計画が出力される。
go、drive、ride でホストを列挙する際は、トークンに `:N` が必須である
(トークンを省略した場合は parent の1スロットとなる)。
例外として、`go --repeat` に限り、列挙したホストの `:N` を省略できる
(そのホストの上限はなくなる)。なお、これらはダッシュボードではない。

go 単体でも十分に実用的である。まず go で単独実行を確認し、
その後 drive、すなわち Distributed.jl への対応へと進めば、段階的に開発できる。
`plan` が ride を提案する場合もある。

### 操作方法

- **CLI** — ターミナルからコマンドとして直接実行する方法。
  例: `julia --project=. -m DistSSHKit go child:user@host1:1 script.jl`。
  手早く試したい場合や、シェルスクリプトに組み込みたい場合に向いている
- **Julia** — 自作の Julia コード (スクリプト、REPL、他のパッケージなど) の中から関数として呼び出す方法。
  `setup!`、`go!`、`plan`、`pool!`、`drive!` などの関数を用いる (`plan` には bang が付かない)
- **`distsshkit` (実験的)** — `pkg> app add DistSSHKit` を実行すると、ターミナルで
  `distsshkit` コマンドを使えるようになる。
  フラグは `-m` と同じだが、常に Apps 側にあるコピーを使用する (`--project=.` ではない)。
  `go`、`setup`、`demo` は `distsshkit` で実行できるが、`drive`、`size`、`pool` は
  `julia --project=. -m DistSSHKit` を使用すること。
  使い分けについては [distsshkit のページ][ug-app] を参照されたい。

CLI のオプションと Julia API は1対1に対応している。
例えば、CLI の `setup --rsync` は `setup!(session, :rsync)` に相当する。
具体例は `demo install with_kit` と `demo install without_kit` のあと
`distsshkit_demos/with_kit/pipeline_square.jl` と
`distsshkit_demos/without_kit/pipeline_pi.jl` を参照されたい。

どちらの方法でも実行内容は同じで、呼び出し方が異なるだけである。まずは CLI から試すと理解しやすい。

### 事前準備

通常は、スクリプトの実行前に `setup` でコードの配置と依存関係を整える。
1回の呼び出しで指定する配置や初期化の操作は、原則として1つのみとする。
リモートが空、または未作成の場合は、`go --rsync` や `drive --rsync` により、コピーと instantiate を一度に行える
(既定の `go` と `drive` は、リモートが準備済みであることを前提とする)。

- 初回配置: `--rsync` (ローカルのツリーをそのまま転送) または `--clone` (git リポジトリを clone) のいずれか一方
- 依存関係の準備: `--instantiate` (リモートで `Pkg.instantiate` を実行)
- 更新 (再配置): `--sync` (git push の後、各リモートで pull)、`--pull`
  (push せず pull のみ)、または `--rsync` の再実行
- その他
  - `--check` (SSH、Julia、依存関係の疎通確認)
  - `up` / `up update` (juliaup でチャネルを揃える。`setup` のフラグではない。確認プロンプトあり、`-y` で省略可)
  - `--prune` (`.distsshkit` 内の go、drive、setup、runs を削除する。配置したツリーは残る)
  - `--cleanup` (残存しているワーカープロセスの掃除)
  - `--delete` (リモートのプロジェクトディレクトリを削除。破壊的な操作である)

`--rsync`、`--clone`、`--sync`、`--pull`、`--delete`、`--prune`、
`up`、`up update` は、実行前に確認プロンプトが表示される。
スクリプトなどで非対話的に実行する場合は、`-y` または `--yes` を付ける。

詳細は
[setup](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/setup/)
を参照されたい。

> [!NOTE]
> **rsync と git のどちらを使うか迷った場合**
>
> - **`--rsync`** — ローカルのファイルをそのまま転送する。リモートに git は不要である。まず試す場合や、単発で使う場合に適している
> - **`--clone` → `--sync`** — git リポジトリとして管理する。コードを継続的に更新しながら使う場合や、
>   `drive --require-git` でリモートの commit がローカルと一致していることを確認したい場合に適している

初回セットアップの典型的な流れは次のとおりである (rsync の場合)。

```bash
# ファイル転送
julia --project=. -m DistSSHKit setup --rsync child:user@host1 child:user@host2
# 依存の用意
julia --project=. -m DistSSHKit setup --instantiate child:user@host1 child:user@host2
# 疎通確認
julia --project=. -m DistSSHKit setup --check child:user@host1 child:user@host2
```

トラブル時によく使うコマンドは次のとおりである。

```bash
# `.distsshkit` の go / drive / setup を消す (配置は残す)
julia --project=. -m DistSSHKit setup --prune child:user@host1 child:user@host2
# 残っている古いワーカープロセスを掃除する
julia --project=. -m DistSSHKit setup --cleanup child:user@host1 child:user@host2
# 全部やり直したいとき (実行確認あり)
julia --project=. -m DistSSHKit setup --delete child:user@host1 child:user@host2
```

### 実行例

事前準備ののち、次のように実行する。

**CLI による go の例。** 各スロットで `script.jl` を最初から最後まで1回ずつ実行する。
`child:user@host:1` はそのホストで1回、`parent:N` はキット起動側で N 回の実行を意味する。
`--repeat N` は合計 N 回の実行を指定する。ホストを併記した場合は、そのホストに割り振られる。

```bash
julia --project=. -m DistSSHKit go \
  child:user@host1:1 child:user@host2:1 path/to/script.jl
julia --project=. -m DistSSHKit go --repeat 100 path/to/script.jl
julia --project=. -m DistSSHKit go --repeat 100 \
  child:user@host1 child:user@host2 path/to/script.jl
```

**CLI による drive の例。** git でデプロイした場合、
2回目以降の更新は `setup --sync` で行う。`rsync` を使ってもよい。

```bash
julia --project=. -m DistSSHKit drive \
  parent:2 child:user@host1:4 path/to/driver.jl
```

**Julia コードによる go の例。** `remote=` は `setup!` と同じ値にそろえる (どちらも省略した場合は既定のパスが使われる)。

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :rsync, :instantiate)
go!("path/to/script.jl", "child:user@host1:1"; remote=remote)
```

**Julia コードによる drive の例。**

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :clone; repo="https://github.com/org/proj.git")
setup!(session, :instantiate)
drive!("path/to/driver.jl", "parent:2", "child:user@host1:4"; remote=remote)
setup!(session, :sync)  # 2回目以降の更新
```

`pipeline!` は、複数の処理をまとめて呼び出すための任意の関数である。sync、`drive!`、collect を一度に実行できる。
ただし `setup!` は含まれない。`sync=:rsync` はコピーのみを行い、instantiate は実行しない。
そのため、リモートをあらかじめ準備しておくか、`drive!(…; sync=:rsync)` を使用すること。
詳細は [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/) を参照されたい。

### デモの実行

自分でスクリプトを書く前に、キットの動作を試すことができる。
`with_kit` は drive、`without_kit` は単独実行および go のデモである。

デモは、ジョブ側のプロジェクト (`pkg> add DistSSHKit` を実行済みのもの) で実行する。
DistSSHKit 自体の checkout 上では実行できない。

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo install without_kit
```

```bash
julia --project=. -m DistSSHKit drive parent:2 distsshkit_demos/with_kit/square_file.jl
julia --project=. -m DistSSHKit go parent:2 distsshkit_demos/without_kit/pi_file.jl
```

詳細は
[Demo](https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/demo/)
を参照されたい。

### キュー

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

**キューホスト。** 常時稼働している macOS または Linux のマシンにログインし、
同じ `pkg> add DistSSHKit` を実行して導入する。
このマシンで実行するコマンドは、すべて `qhost` で始まる。
`qhost:HOST` の形式は受け付けない。
既定の Julia 環境で動作するため、`--project=.` は付けない。

```bash
julia -m DistSSHKit qhost setup
julia -m DistSSHKit qhost add-host parent child:host1
julia -m DistSSHKit qhost serve
```

`qhost enable` を実行すると、再起動後にも `serve` が自動的に起動する。

**クライアント。** ジョブはクライアント側のマシンに置いたままにする。
`qhost:HOST` にはキューホストの SSH 名を指定し、
`submit`、`status`、`fetch`、`cancel` の前に付ける。
この接続では、キューホストの `~/.distsshqueue/env` が使われる。
その環境の作成方法は [Prepare][q-prepare] を参照されたい。

```bash
julia --project=. -m DistSSHKit qhost:HOST submit go parent:1 distsshkit_demos/without_kit/pi_echo.jl
```

詳細は [Prepare][q-prepare]、[Walkthrough][q-walk]、
[Queue][q-manual] を参照されたい。

## ドキュメント

公式ドキュメントの本体は英語である。

- Introduction:
  [Introduction](https://yamanori99.github.io/DistSSHKit.jl/stable/)
- First Steps:
  [First Steps](https://yamanori99.github.io/DistSSHKit.jl/stable/requirements/)
- Queue: [Walkthrough][q-walk]
- User Guide:
  [User Guide](https://yamanori99.github.io/DistSSHKit.jl/stable/manual/)
- API: [API](https://yamanori99.github.io/DistSSHKit.jl/stable/api/)
- News: [NEWS.md](NEWS.md). Through 0.9.0: [HISTORY.md](HISTORY.md).

## 貢献

バグの報告や機能の要望は
[Issues](https://github.com/yamanori99/DistSSHKit.jl/issues) へ、
質問やアイデアは
[Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions)
へお寄せください。
貢献の方法は [CONTRIBUTING.md](CONTRIBUTING.md) を参照されたい。

## ライセンス

ソースコードは [MIT](LICENSE) ライセンスである。ロゴと図に含まれる Julia のドットは
Copyright (c) 2012-2022 Stefan Karpinski によるもので、
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)
のもとで提供されている。
DistSSHKit では、これを改変して使用している。
詳細は [LICENSE](LICENSE) と
[julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics) を参照されたい。

<!-- markdownlint-disable MD013 -->
[ug-app]: https://yamanori99.github.io/DistSSHKit.jl/stable/manual/distsshkit/
[q-prepare]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/queue-prepare/
[q-walk]: https://yamanori99.github.io/DistSSHKit.jl/stable/tutorial/queue-walkthrough/
[q-manual]: https://yamanori99.github.io/DistSSHKit.jl/stable/queue/
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
      alt="DistSSHKit.jl logo"/>
  </picture>
</p>
<!-- markdownlint-enable MD033 MD013 -->
