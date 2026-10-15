# DistSSHKit.jl

[English](README.md) · [日本語](README.ja.md)

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

DistSSHKitは、SSHを介して複数のマシン上でJuliaによる計算を実行するためのツールキットである。

ワークステーション2台の小規模な構成から、研究室にある多数のマシンを利用する構成まで対応する。

対応環境はmacOS、Linux、およびWSL2上のUbuntuである（Windowsネイティブ環境には非対応）。

DistSSHKitは、Juliaのパッケージモードで `add DistSSHKit` を実行することでインストールできる。各コマンドは、ターミナルから `julia -m DistSSHKit` にサブコマンドを続けて実行する。

DistSSHKitは、DistSSHRunとDistSSHQueueを依存関係として持つメタパッケージである。両パッケージは自動的にインストールされるため、個別に導入する必要はない。

ジョブの実行を開始する方法は、次の2種類である。

- **手元のマシンから実行する場合。** このマシンからジョブを開始する。リモートマシンを利用する場合、ジョブが完了するまでSSH接続が維持される。ジョブの実行には `go`、`ride`、`drive` を使用し、実行計画の確認や補助的な操作には `plan`、`size`、`pool`、`demo`、`progress` を利用できる。
- **キューホスト。** 常時稼働するマシンであり、登録されたジョブをキュー（待ち行列）で管理し、先に登録されたものから順番に実行する。

ホストの事前準備は、手元のマシンからジョブを実行する場合と、キューホストを利用する場合の両方に共通する。

SSH接続先の環境を準備するには `setup` を使用する。また、必要に応じて `up` を使用し、各マシンのJuliaのチャネル（バージョン系列）を揃える。

## インストール

JuliaのREPLで `]` キーを押してPkgモードに切り替え、次のコマンドを実行する。

```julia
pkg> add DistSSHKit
```

また、Pkg APIを使用してインストールすることもできる。

```julia
julia> import Pkg; Pkg.add("DistSSHKit")
```

SSH経由で別のマシンを利用する場合、実行元のマシンには `ssh` と `rsync` が必要となる。Gitを使用してデプロイする場合は、さらに `git` も必要となる。

これらはJuliaのパッケージとは別のツールであり、`pkg> add DistSSHKit` ではインストールされない。動作要件の詳細については、[Requirements][req]を参照する。

DistSSHKitの機能や使用方法については、[公式ドキュメント][home]を参照する。

## 使用方法

### 基本用語

- **ホスト** — 計算に利用するマシン。`parent` や `child:user@hostname` などの指定文字列（トークン）を用いて指定する。
- **プロセス** — 実行中の `julia` に対応するOS上の実行単位。各プロセスは独立したメモリ空間を持ち、OSによって個別に管理される。DistSSHKitでは、1台のマシン上でも複数のJuliaプロセスを起動し、並列に処理を実行できる。
- **マスター** — ジョブの実行を管理するプロセス。`go` ではスロットの割り当てを計画し、`drive` ではワーカーへの処理の割り振りと結果の回収を担当する。
- **ワーカー** — マスターから割り当てられた処理を実行するプロセス。`drive` や `ride` では、Distributed.jlのワーカーを利用する。

手元のマシンから `go` や `drive` を実行する場合、そのマシンが実行元となる。一方、キューホストにジョブを登録した場合は、キューホストが実行元となる。

`drive` では、1台のマシン上で複数のワーカーを起動できる。実行元のマシンにワーカーを配置せず、リモートマシン上のワーカーのみを利用することも可能である。

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

上図は `drive` の構成を示している。実行元のマシンに1つのマスターがあり、指定したホスト上のワーカーに処理を分配する。

`go` でもホストの指定方法は共通しているが、`drive` のようなマスター・ワーカー関係はなく、各スロットでスクリプトを独立して実行する。

```text
parent                 # 実行元のマシン
parent:2               # 実行元のマシンに2スロットを指定
child:user@hostname    # SSH接続先のマシン
child:user@hostname:4  # SSH接続先のマシンに4スロットを指定
```

SSH接続先のホスト数に固定の上限は設けていない。ただし、接続先が増えるほどSSH接続やプロジェクトの配置に要する時間も増加するため、まずは少数のマシンから試すことを推奨する。

SSH接続先のマシンは、次の条件を満たす必要がある。

- 実行元のマシンから、公開鍵認証などを利用してパスワード入力なしでSSH接続できること
- Juliaがインストールされており、実行元のマシンとメジャー・マイナーバージョンが一致していること（`setup --check` で確認できる。必要に応じて `up` でJuliaのチャネルを揃える）

動作要件の詳細については、[Requirements][req]を参照する。

### 実行元のマシンから実行する場合：go、ride、drive

実行方式は次の3種類である。

- **`go`** — 指定された `.jl` ファイルを、各スロットで最初から最後まで独立して実行する。
- **`ride`** — `map`、`filter`、内包表記、添字を用いた `for` ループなど、条件を満たす独立した処理を分割し、並列実行を試みる（実験的機能。実行元のマシンおよびSSH接続先で利用可能）。
- **`drive`** — Distributed.jlを利用し、1つのマスターが複数のワーカーに処理を分配する。

### 事前確認：plan（スクリプト）とpool（ホスト）

- **`plan`** — `.jl` ファイルの構文を解析し、`go`、`ride`、`drive` の実行方式の候補を提案する。通常はファイルの読み込みと構文解析のみを行い、SSH接続やジョブの実行は行わない。追加オプションを指定することで、`size!` によるスロット数の見積もりも可能である。
- **`pool` / `pool!`** — 指定したホストのCPUコア数とRAM容量を取得し、スロット数の目安を示す。リモートホストの情報取得にはSSHを使用するが、RSS（プロセスの物理メモリ使用量）は計測しない。接続できないホストも結果から除外せず、`ok=false` として記録する。

`size` / `size!` は、CPUやメモリの情報をもとに、実行可能なワーカー数を見積もる機能である。必要に応じてRSS（プロセスの物理メモリ使用量）を計測し、実行計画（`WorkerPlan`）の作成に利用する。CLIの `size` では、この実行計画を表示する。

`go`、`drive`、`ride` でホストを指定する場合は、各ホストの指定文字列に `:N` を付けてスロット数を明示する必要がある。ホストを指定しない場合は、実行元のマシンに1スロットが割り当てられる。

ただし、`go --repeat` では例外的に `:N` を省略できる。この場合、そのホストのスロット数に明示的な上限は設けられない。

これらは実行計画の確認を目的とした機能であり、リアルタイムの監視を行うダッシュボードではない。

`go` は、独立したスクリプトの実行に利用できる。まず `go` でスクリプトが正常に実行できることを確認し、必要に応じてDistributed.jlを利用する `drive` に移行することで、段階的に開発を進められる。なお、`plan` が `ride` を実行方式の候補として提案する場合もある。

### 操作方法

DistSSHKitには、次の2つの操作方法がある。

- **CLI** — ターミナルからコマンドを実行する方法。手軽に試したい場合や、シェルスクリプトに組み込む場合に適している。
  例：`julia --project=. -m DistSSHKit go child:user@host1:1 script.jl`
- **Julia API** — Juliaのコード（スクリプト、REPL、他のパッケージなど）から関数を呼び出す方法。`setup!`、`go!`、`plan`、`pool!`、`drive!` などの関数を使用する。

CLIの操作は、Julia APIからも同様に実行できる。例えば、CLIの `setup --rsync` は、Julia APIの `setup!(session, :rsync)` に相当する。

具体的な使用例は、`demo install with_kit` および `demo install without_kit` でデモをインストールした後、生成される `distsshkit_demos/with_kit/pipeline_square.jl` と `distsshkit_demos/without_kit/pipeline_pi.jl` を参照する。

どちらの方法でも同等の操作が可能だが、初めて利用する場合はCLIから試すと理解しやすい。

### 事前準備

通常は、スクリプトの実行前に `setup` を使用し、リモートマシンへのプロジェクトの配置と依存パッケージの準備を行う。CLIの `setup` では、1回の呼び出しにつき1つの操作モードを指定する。

リモートマシン上のプロジェクト配置先が存在しない、または空の場合は、`go --rsync` や `drive --rsync` を使用することで、ファイルの転送と必要に応じた依存パッケージのインストールを一度に行える。通常の `go` と `drive` は、リモート環境が準備済みであることを前提とする。

- **初回配置**
  - `--rsync`：ローカルのプロジェクトファイルをリモートマシンに転送する。
  - `--clone`：リモートマシン上でGitリポジトリを複製する。
  - 初回配置では、いずれか一方を指定する。
- **依存パッケージの準備**
  - `--instantiate`：リモートマシン上で `Pkg.instantiate` を実行し、依存パッケージを用意する。
- **更新**
  - `--sync`：ローカルで `git push` を実行した後、各リモートマシンで `git pull` を実行する。
  - `--pull`：ローカルと各リモートマシンで順番に `git pull` を実行する。`git push` は行わない。
- **その他の操作**
  - `--check`：SSH接続、Juliaの実行環境、プロジェクトや依存パッケージの状態などを確認する。
  - `up` / `up update`：juliaupを使用してJuliaのチャネルを設定・更新する。`setup` とは独立したコマンドであり、実行前に確認が求められる（`-y` で省略可能）。
  - `--prune`：ローカルおよびリモートの `.distsshkit` 内にある `go`、`drive`、`setup`、`runs` の実行関連データを削除する。配置済みのプロジェクトは削除しない。
  - `--cleanup`：残存しているJuliaのワーカープロセスを終了する。
  - `--delete`：リモートマシン上のプロジェクト配置先を削除する。実行時には注意が必要である。

`--rsync`、`--clone`、`--sync`、`--pull`、`up`、`up update` は、実行前に確認を求める。スクリプトなどから非対話的に実行する場合は、`-y` または `--yes` を指定することで確認を省略できる。

`--delete` と `--prune` では、削除前にそれぞれ `delete` または `prune` の入力が求められる。現行バージョンでは、`-y` または環境変数 `DISTSSHKIT_YES` によって、この確認を省略して削除を実行できる。ただし、この動作はDistSSHKit 0.11（DistSSHRun 0.2）で廃止される予定であり、以降は `--confirm-path` による削除対象パスの確認を使用する。

キューホストの管理データなどを削除する `teardown` は、`--confirm-path` を指定しない場合、`Would remove` と表示して削除を行わない。ただし、現行バージョンでは `-y` または `DISTSSHKIT_YES` を指定すると削除が実行される。この動作もDistSSHKit 0.11（DistSSHQueue 0.10）で廃止される予定である。

詳細は[`setup`][m-setup]を参照する。

> [!NOTE]
> **rsyncとGitのどちらを使用するか迷った場合**
>
> - **`--rsync`** — ローカルのプロジェクトファイルをリモートマシンに転送する。リモートマシンでのGitによる管理は不要であり、初めて利用する場合や単発の実行に適している。
> - **`--clone` → `--sync`** — `--clone` でGitリポジトリを複製し、以降の更新を `--sync` で行う。コードを継続的に更新する場合や、`drive --require-git` を使用して実行元とリモートマシンのGitコミットが一致していることを確認し、再現性を高めたい場合に適している。

初回セットアップの基本的な手順は次のとおりである（rsyncを使用する場合）。

```bash
# プロジェクトファイルの転送
julia --project=. -m DistSSHKit setup --rsync child:user@host1 child:user@host2

# 依存パッケージの準備
julia --project=. -m DistSSHKit setup --instantiate child:user@host1 child:user@host2

# SSH接続・実行環境の確認
julia --project=. -m DistSSHKit setup --check child:user@host1 child:user@host2
```

実行環境の管理やトラブルへの対処に使用するコマンドは次のとおりである。

```bash
# .distsshkit 内の実行関連データを削除する（配置済みのプロジェクトは保持する）
julia --project=. -m DistSSHKit setup --prune child:user@host1 child:user@host2

# 残存しているワーカープロセスを終了する
julia --project=. -m DistSSHKit setup --cleanup child:user@host1 child:user@host2

# リモートマシンのプロジェクト配置先を削除する
# 現行の0.10系では -y を指定すると削除確認が省略されるため注意する
julia --project=. -m DistSSHKit setup --delete child:user@host1 child:user@host2
```

### 実行例

事前準備が完了したら、次のように実行する。

**CLIによる `go` の実行例。**

各スロットで `script.jl` を最初から最後まで1回ずつ実行する。`child:user@host:1` は指定したリモートホストで1回、`parent:N` は実行元のマシンでN回実行することを意味する。

`--repeat N` は、合計N回の実行を指定するオプションである。複数のホストを指定した場合は、それらのホストに実行が振り分けられる。

```bash
julia --project=. -m DistSSHKit go \
  child:user@host1:1 child:user@host2:1 path/to/script.jl

julia --project=. -m DistSSHKit go --repeat 100 path/to/script.jl

julia --project=. -m DistSSHKit go --repeat 100 \
  child:user@host1 child:user@host2 path/to/script.jl
```

**CLIによる `drive` の実行例。**

Gitを使用してプロジェクトを配置した場合、以降の更新には `setup --sync` を使用する。`rsync` によるファイル転送も利用できる。

```bash
julia --project=. -m DistSSHKit drive \
  parent:2 child:user@host1:4 path/to/driver.jl
```

**Julia APIによる `go` の実行例。**

`remote` には、リモートマシン上のプロジェクト配置先を指定する。`KitSession` と `go!` で同じ値を使用する必要がある。どちらも省略した場合は、既定のパスが使用される。

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :rsync, :instantiate)
go!("path/to/script.jl", "child:user@host1:1"; remote=remote)
```

**Julia APIによる `drive` の実行例。**

```julia
using DistSSHKit

remote = "/path/to/project"
session = KitSession(workers=["child:user@host1"], remote=remote, yes=true)
setup!(session, :clone; repo="https://github.com/org/proj.git")
setup!(session, :instantiate)
drive!("path/to/driver.jl", "parent:2", "child:user@host1:4"; remote=remote)
setup!(session, :sync)  # 2回目以降の更新
```

`pipeline!` は、必要に応じたファイルの同期、`drive!` による実行、結果の回収（collect）をまとめて行うための補助関数である。

ただし、`pipeline!` には `setup!` による事前準備は含まれない。また、`sync=:rsync` を指定した場合はファイルの転送のみを行い、`instantiate` による依存パッケージの準備は実行されない。

そのため、あらかじめリモート環境を準備しておく必要がある。依存パッケージが不足している場合に自動で準備したい場合は、`drive!(…; sync=:rsync)` を使用する。

詳細は[API][api]を参照する。

### デモの実行

自分でスクリプトを作成する前に、用意されているデモを使用してDistSSHKitの動作を確認できる。

- **`with_kit`** — `drive` を使用した分散実行のデモ。
- **`without_kit`** — 通常のJuliaスクリプトとしての単独実行や、`go` による並列実行のデモ。

デモのインストールと実行は、DistSSHKitを依存パッケージとして追加した、ジョブ用のJuliaプロジェクトで行う。

DistSSHKit自体のソースコードがあるディレクトリには、デモを直接インストールできない。開発中に別の場所へインストールする場合は、`--dest` でインストール先を指定する。

**デモのインストール**

```bash
julia --project=. -m DistSSHKit demo install with_kit
julia --project=. -m DistSSHKit demo install without_kit
```

**デモの実行**

```bash
# driveによる分散実行
julia --project=. -m DistSSHKit drive parent:2 distsshkit_demos/with_kit/square_file.jl

# goによる独立したスクリプトの並列実行
julia --project=. -m DistSSHKit go parent:2 distsshkit_demos/without_kit/pi_file.jl
```

どちらの例も、実行元のマシンに2つのスロットを指定している。

詳細は[Demo][t-demo]を参照する。

### キューホスト

キューホストは、ジョブを待ち行列で管理し、順番に実行するための常時稼働マシンである。ジョブはFIFO（先入れ先出し）方式で管理され、原則として一度に1件ずつ実行される。

```text
  client (開発用マシン)                 queue host (常時稼働)
  --------------------                 --------------------
  ジョブ用プロジェクト                 FIFO: 一度に1件ずつ実行
       |                               管理データ ~/.distsshqueue/
       |  qhost:HOST submit             qhost setup / add-host
       |  status / fetch / cancel       qhost serve / enable
       +------------------------------> go / ride / drive
                                       -> workers (parent / child:)
```

**キューホスト側**

常時稼働するmacOSまたはLinuxのマシンにログインし、Juliaのパッケージモードで `add DistSSHKit` を実行してインストールする。

キューホストの初期設定や実行管理には、`qhost setup`、`qhost add-host`、`qhost serve` などのコマンドを使用する。これらはキューホスト上で直接実行するため、`qhost:HOST` は付けない。

次の例では、Juliaの既定の環境にDistSSHKitをインストールしていることを前提としているため、`--project=.` は指定しない。

```bash
# キューホストの初期設定
julia -m DistSSHKit qhost setup

# 利用するホストの登録
julia -m DistSSHKit qhost add-host parent child:host1

# ジョブの処理を開始
julia -m DistSSHKit qhost serve
```

ここで `parent` はキューホスト自身、`child:host1` はキューホストからSSH接続するリモートマシンを指す。

`qhost enable` を実行すると、OSのサービス機能を利用し、再起動後やログイン後にも `serve` が自動的に起動するように設定できる。

**クライアント側**

クライアントは、ジョブの登録や実行状況の確認、結果の取得などを行うマシンである。

`qhost:HOST` の `HOST` には、キューホストのSSH接続先名を指定する。クライアントから操作する場合は、`submit`、`status`、`fetch`、`cancel` などのコマンドの前に `qhost:HOST` を付ける。

`qhost:HOST submit` を実行すると、クライアント上のジョブ用プロジェクトがキューホストにコピーされ、ジョブが待ち行列に登録される。元のプロジェクトはクライアント側にも残る。

```bash
# キューホストにジョブを登録
julia --project=. -m DistSSHKit qhost:HOST submit go parent:1 distsshkit_demos/without_kit/pi_echo.jl
```

この例では、キューホスト自身に1スロットを割り当て、`go` でスクリプトを実行する。

`qhost:HOST` による接続では、既定でキューホスト上の `~/.distsshqueue/env` がJuliaの実行環境として使用される。この環境にはDistSSHKitをインストールしておく必要がある。

環境の準備方法や詳しい操作手順については、[Prepare][q-prepare]、[Walkthrough][q-walk]、[How it runs][q-manual]を参照する。

## ドキュメント

公式ドキュメントの本体は英語である。ページ名も英語のままである。

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
- News: [NEWS.md](NEWS.md). Through 0.9.0: [HISTORY.md](HISTORY.md).

## パッケージ

- [DistSSHKit][home] `ceec0504-c968-4be5-b215-667cae0e8f81`
- [DistSSHRun][run] `b568025c-2759-4ef1-8b14-17d00e2cd000`
- [DistSSHQueue][queue] `24254401-70d8-4a51-8ea4-cfab19f5bc73`

## 貢献

バグの報告や機能の要望は
[Issues](https://github.com/yamanori99/DistSSHKit.jl/issues) へ、
質問やアイデアは
[Discussions](https://github.com/yamanori99/DistSSHKit.jl/discussions)
へお寄せください。
貢献の方法は [CONTRIBUTING.md](CONTRIBUTING.md) を参照されたい。

## ライセンス

ソースコードは [MIT](LICENSE) ライセンスである。ロゴと図に含まれるJuliaのドットは
Copyright (c) 2012-2022 Stefan Karpinski によるもので、
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)
のもとで提供されている。
DistSSHKitでは、これを改変して使用している。
詳細は [LICENSE](LICENSE) と
[julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics) を参照されたい。

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
      alt="DistSSHKit.jl logo"/>
  </picture>
</p>
<!-- markdownlint-enable MD033 MD013 -->
