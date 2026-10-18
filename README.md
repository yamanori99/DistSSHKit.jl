# Compile bench

Precompile time, load time, CLI wall time, `src/**/*.jl` size, and the host
(OS name, arch, CPU). `code lines` skips blank lines. A row is flagged when,
against the previous sample on the same Julia slot, the host OS or arch
changes, package precompile grows by 1.5x and 0.5s, a command wall grows
by 1.5x and 1s, or a method of at least 200 ms is new in the top 20 or
doubles. This does not fail CI.

## Flagged

No sample grew past the watch line.

## 1.13

| date | commit | version | os | arch | src files | code lines | full s | pkg s | using s | help s | status s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-18 | 81ff9d1 | 0.10.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 407 | 9.21 | 1.02 | 0.32 | 15.61 | 16.38 |

```mermaid
xychart-beta
    title "1.13 help"
    x-axis ["1018"]
    y-axis "seconds" 0 --> 19
    bar [15.61]
```


Latest `help` methods:

| method | now ms | previous ms |
| --- | ---: | ---: |
| `Tuple{typeof(DistSSHKit.main), Array{String, 1}}` | 14966.0 |  |
| `Tuple{typeof(DistSSHKit.print_kit_root_usage), Base.PipeEndpoint}` | 74.5 |  |
| `Tuple{Distributed.var"#start_gc_msgs_task##0#start_gc_msgs_task##1"}` | 17.8 |  |
| `Tuple{typeof(Base.should_use_main_entrypoint)}` | 11.3 |  |
| `Tuple{typeof(Base.getproperty), Base.MappingRF{DistSSHRun.var"#67#68", typeof(Base.max)}, ...` | 5.7 |  |
| `Tuple{typeof(Base.getproperty), Base.Order.By{DistSSHQueue.var"#sorted_kit_ssh_names##0#so...` | 5.6 |  |
| `Tuple{typeof(Base.in), String, Tuple{String, String, String}}` | 5.5 |  |
| `Tuple{typeof(Base.getproperty), Base.MappingRF{DistSSHRun.var"#77#78", typeof(Base.max)}, ...` | 5.2 |  |
| `Tuple{typeof(Base.getproperty), NamedTuple{(:quiet, :progress, :verbose, :yes, :hosts_file...` | 5.0 |  |
| `Tuple{typeof(Base.getproperty), Base.Order.By{DistSSHRun.var"#_kit_progress_files##0#_kit_...` | 4.8 |  |

```mermaid
xychart-beta
    title "1.13 status"
    x-axis ["1018"]
    y-axis "seconds" 0 --> 20
    bar [16.38]
```


Latest `status` methods:

| method | now ms | previous ms |
| --- | ---: | ---: |
| `Tuple{typeof(DistSSHKit.main), Array{String, 1}}` | 15382.8 |  |
| `Tuple{DistSSHQueue.var"##show_status#192", Base.PipeEndpoint, Nothing, Bool, Nothing, Bool...` | 608.0 |  |
| `Tuple{Distributed.var"#start_gc_msgs_task##0#start_gc_msgs_task##1"}` | 17.8 |  |
| `Tuple{typeof(Base.should_use_main_entrypoint)}` | 11.3 |  |
| `Tuple{typeof(Core.kwcall), NamedTuple{(:quiet, :tail, :verbose), Tuple{Bool, Nothing, Bool...` | 6.9 |  |
| `Tuple{typeof(Base._array_for), Type{DistSSHQueue.Job}, Array{Any, 1}, Base.HasShape{1}}` | 6.6 |  |
| `Tuple{typeof(Base.in), String, Tuple{String, String, String}}` | 5.9 |  |
| `Tuple{typeof(Base.getproperty), Base.MappingRF{DistSSHRun.var"#67#68", typeof(Base.max)}, ...` | 5.7 |  |
| `Tuple{typeof(Base.getproperty), Base.MappingRF{DistSSHRun.var"#77#78", typeof(Base.max)}, ...` | 5.6 |  |
| `Tuple{typeof(Base.getproperty), Base.Generator{Base.Pairs{Symbol, Union{}, Nothing, NamedT...` | 5.5 |  |

## 1.14-nightly

| date | commit | version | os | arch | src files | code lines | full s | pkg s | using s | help s | status s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-18 | 81ff9d1 | 0.10.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 407 | 8.48 | 0.91 | 0.35 | 7.06 | 7.15 |

```mermaid
xychart-beta
    title "1.14-nightly help"
    x-axis ["1018"]
    y-axis "seconds" 0 --> 9
    bar [7.06]
```


Latest `help` methods:

| method | now ms | previous ms |
| --- | ---: | ---: |
| `Tuple{typeof(DistSSHKit.main), Array{String, 1}}` | 17077.1 |  |
| `Tuple{typeof(DistSSHKit.print_kit_root_usage), Base.PipeEndpoint}` | 87.4 |  |
| `Tuple{typeof(Distributed.flush_gc_msgs)}` | 23.7 |  |
| `Tuple{Distributed.var"#start_gc_msgs_task##0#start_gc_msgs_task##1"}` | 15.5 |  |
| `Tuple{typeof(Base.should_use_main_entrypoint)}` | 13.7 |  |
| `Tuple{typeof(DistSSHRun.DistSSHBase.format_placement_token), Symbol, String, Nothing}` | 9.9 |  |
| `Tuple{typeof(Base.getproperty), NamedTuple{(:quiet, :progress, :verbose, :yes, :hosts_file...` | 9.5 |  |
| `Tuple{typeof(Base.getproperty), Pair{String, Int64}, Symbol}` | 6.8 |  |
| `Tuple{typeof(Base.getproperty), Base.Generator{Tuple{String, String, String}, DistSSHRun.v...` | 6.7 |  |
| `Tuple{typeof(Base.in), String, Tuple{String, String, String}}` | 6.6 |  |

```mermaid
xychart-beta
    title "1.14-nightly status"
    x-axis ["1018"]
    y-axis "seconds" 0 --> 9
    bar [7.15]
```


Latest `status` methods:

| method | now ms | previous ms |
| --- | ---: | ---: |
| `Tuple{typeof(DistSSHKit.main), Array{String, 1}}` | 6511.7 |  |
| `Tuple{DistSSHQueue.var"##show_status#192", Base.PipeEndpoint, Nothing, Bool, Nothing, Bool...` | 541.6 |  |
| `Tuple{typeof(Distributed.flush_gc_msgs)}` | 25.4 |  |
| `Tuple{Distributed.var"#start_gc_msgs_task##0#start_gc_msgs_task##1"}` | 14.7 |  |
| `Tuple{typeof(Core.kwcall), NamedTuple{(:quiet, :tail, :verbose), Tuple{Bool, Nothing, Bool...` | 13.5 |  |
| `Tuple{typeof(Base._array_for), Core.TypeEgal{DistSSHQueue.Job}, Array{Any, 1}, Base.HasSha...` | 7.1 |  |
| `Tuple{Core.TypeEgal{Base.LinearIndices{N, R} where R<:Tuple{Vararg{Base.AbstractUnitRange{...` | 3.7 |  |
| `Tuple{Base.var"##187#188", Vararg{Any, 4}}` | 3.5 |  |
| `Tuple{typeof(Base.should_use_main_entrypoint)}` | 2.8 |  |
| `Tuple{typeof(DistSSHRun.DistSSHBase.format_placement_token), Symbol, String, Nothing}` | 1.6 |  |

