# Compile bench

The charts are on [bench.html](https://yamanori99.github.io/DistSSHKit.jl/bench.html).

Precompile time, load time, CLI wall time, `src/**/*.jl` size, and the host
(OS name, arch, CPU). `code lines` skips blank lines. A row is flagged when,
against the previous sample on the same Julia slot, the host OS or arch
changes, the Julia version changes, package precompile grows by 1.5x and 0.5s, a command wall grows
by 1.5x and 1s, or a method of at least 200 ms is new in the top 20 or
doubles. This does not fail CI. Each slot's table folds. The 1.13
table starts open.

## Flagged

- 1.13: status method new -> 757.7 ms: Tuple{DistSSHQueue.var"##show_status#223", Base.PipeEndpoint, Nothing, Bool, Nothing, Bool, typeof(D...
- 1.13: go method new -> 1108.0 ms: Tuple{typeof(Core.kwcall), NamedTuple{(:project, :quiet, :verbosity, :yes, :args, :path_anchor, :out...
- 1.14-pre: status method new -> 424.8 ms: Tuple{DistSSHQueue.var"##show_status#223", Base.PipeEndpoint, Nothing, Bool, Nothing, Bool, typeof(D...
- 1.14-pre: go method new -> 747.4 ms: Tuple{typeof(Core.kwcall), NamedTuple{(:project, :quiet, :verbosity, :yes, :args, :path_anchor, :out...
- nightly: julia 1.15.0-DEV.631 -> 1.15.0-DEV.649
- nightly: status method new -> 653.4 ms: Tuple{DistSSHQueue.var"##show_status#223", Base.PipeEndpoint, Nothing, Bool, Nothing, Bool, typeof(D...
- nightly: go method new -> 1180.6 ms: Tuple{typeof(Core.kwcall), NamedTuple{(:project, :quiet, :verbosity, :yes, :args, :path_anchor, :out...

<details open>
<summary>1.13</summary>

| date | commit | version | julia | os | arch | src files | code lines | full s | pkg s | using s | help s | status s | go s | drive s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-02 | d4f4508 | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 26.18 | 1.04 | 0.39 | 1.12 | 4.15 | 6.8 | 18.65 |
| 2026-11-03 | f3f63c1 | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 29.07 | 1.17 | 0.44 | 1.25 | 4.54 | 7.52 | 20.12 |
| 2026-11-04 | f3f63c1 | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 27.65 | 1.12 | 0.41 | 1.2 | 4.57 | 7.39 | 19.42 |
| 2026-11-05 | 7b0d80e | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 28.94 | 1.14 | 0.42 | 1.23 | 4.5 | 7.52 | 19.8 |
| 2026-11-06 | ddcdf8b | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 18.67 | 0.79 | 0.29 | 0.84 | 2.99 | 4.92 | 13.66 |
| 2026-11-06 | 9812d68 | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 18.29 | 0.78 | 0.27 | 0.83 | 3.07 | 5.2 | 14.25 |
| 2026-11-07 | 9812d68 | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 17.37 | 0.77 | 0.26 | 0.8 | 2.96 | 5.05 | 13.69 |
| 2026-11-08 | b13130d | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 26.88 | 1.08 | 0.39 | 1.2 | 4.43 | 7.32 | 19.08 |
| 2026-11-08 | fe6cc4f | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 20.9 | 0.84 | 0.32 | 0.93 | 3.57 | 5.91 | 15.93 |
| 2026-11-09 | fe6cc4f | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 17.29 | 0.8 | 0.27 | 0.84 | 3.1 | 4.98 | 13.94 |
| 2026-11-10 | 854dacb | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 27.49 | 1.03 | 0.39 | 1.13 | 4.25 | 5.3 | 17.87 |
| 2026-11-11 | 5926f8a | 0.11.0-DEV | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 29.3 | 1.1 | 0.42 | 1.2 | 4.43 | 5.48 | 18.57 |

</details>

<details>
<summary>1.14-nightly</summary>

| date | commit | version | julia | os | arch | src files | code lines | full s | pkg s | using s | help s | status s | go s | drive s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-19 | 72e0a48 | 0.10.2 | 1.14.0-DEV.3787 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 410 | 6.69 | 0.77 | 0.32 | 0.57 | 6.14 | 3.09 | 12.02 |
| 2026-10-20 | b02f4dd | 0.10.2 | 1.14.0-DEV.3787 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 6.44 | 0.82 | 0.29 | 0.55 | 1.6 | 2.72 | 10.27 |
| 2026-10-20 | d1bb1de | 0.10.3 | 1.14.0-DEV.3787 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 5.62 | 0.72 | 0.25 | 0.49 | 1.43 | 2.45 | 9.49 |
| 2026-10-20 | 33ecf3a | 0.10.3 | 1.14.0-alpha1 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 8.0 | 0.83 | 0.35 | 0.66 | 1.96 | 3.37 | 12.57 |
| 2026-10-21 | 0d024d1 | 0.10.3 | 1.14.0-alpha1 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 6.51 | 0.87 | 0.28 | 0.58 | 1.67 | 2.93 | 10.35 |
| 2026-10-22 | 2e838fd | 0.10.4 | 1.14.0-alpha1 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 415 | 7.39 | 0.79 | 0.32 | 0.59 | 1.77 | 3.06 | 11.55 |
| 2026-10-23 | 2e838fd | 0.10.4 | 1.14.0-alpha1 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 7.15 | 0.74 | 0.3 | 0.56 | 1.79 | 3.38 | 11.32 |
| 2026-10-24 | ac1ce0f | 0.10.5 | 1.14.0-alpha1 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 8.17 | 0.85 | 0.37 | 0.64 | 2.17 | 4.31 | 13.76 |
| 2026-10-24 | 7edf0c1 | 0.10.5 | 1.14.0-alpha1 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 9.48 | 0.93 | 0.37 | 0.69 | 2.27 | 4.31 | 13.71 |
| 2026-10-25 | f610f7c | 0.10.6 | 1.14.0-alpha1.112 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 7.39 | 0.8 | 0.26 | 0.63 | 1.83 | 3.4 | 11.44 |
| 2026-10-26 | 399faf6 | 0.10.6 | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 9.17 | 0.9 | 0.3 | 0.72 | 2.5 | 4.06 | 13.5 |
| 2026-10-27 | 399faf6 | 0.10.6 | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 10.6 | 1.06 | 0.36 | 0.87 | 3.07 | 4.83 | 15.54 |

</details>

<details>
<summary>1.14-pre</summary>

| date | commit | version | julia | os | arch | src files | code lines | full s | pkg s | using s | help s | status s | go s | drive s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-02 | d4f4508 | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 24.41 | 0.97 | 0.34 | 0.77 | 1.76 | 3.59 | 10.41 |
| 2026-11-03 | f3f63c1 | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 26.18 | 1.04 | 0.38 | 0.83 | 1.92 | 3.94 | 11.35 |
| 2026-11-04 | f3f63c1 | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 22.57 | 0.92 | 0.34 | 0.74 | 1.66 | 3.45 | 10.02 |
| 2026-11-05 | 7b0d80e | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 24.71 | 0.97 | 0.34 | 0.77 | 1.75 | 3.67 | 10.55 |
| 2026-11-06 | ddcdf8b | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 19.36 | 0.8 | 0.28 | 0.64 | 1.41 | 2.94 | 8.63 |
| 2026-11-06 | 9812d68 | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 21.89 | 0.95 | 0.35 | 0.75 | 1.67 | 3.49 | 10.02 |
| 2026-11-07 | 9812d68 | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 23.32 | 0.95 | 0.34 | 0.74 | 1.74 | 3.65 | 10.31 |
| 2026-11-08 | b13130d | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 23.81 | 0.99 | 0.34 | 0.78 | 1.77 | 3.68 | 10.49 |
| 2026-11-08 | fe6cc4f | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 19.02 | 0.85 | 0.3 | 0.68 | 1.52 | 3.19 | 8.63 |
| 2026-11-09 | fe6cc4f | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 16.81 | 0.78 | 0.28 | 0.62 | 1.38 | 3.13 | 8.79 |
| 2026-11-10 | 854dacb | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 24.14 | 1.02 | 0.37 | 0.75 | 1.75 | 2.72 | 10.0 |
| 2026-11-11 | 5926f8a | 0.11.0-DEV | 1.14.0-alpha2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 17.17 | 0.72 | 0.24 | 0.62 | 1.26 | 2.02 | 7.59 |

</details>

<details>
<summary>nightly</summary>

| date | commit | version | julia | os | arch | src files | code lines | full s | pkg s | using s | help s | status s | go s | drive s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-02 | d4f4508 | 0.11.0-DEV | 1.15.0-DEV.337 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 25.32 | 0.96 | 0.32 | 0.74 | 1.88 | 3.82 | 10.74 |
| 2026-11-03 | f3f63c1 | 0.11.0-DEV | 1.15.0-DEV.402 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 25.15 | 0.88 | 0.28 | 0.71 | 1.78 | 3.64 | 10.58 |
| 2026-11-04 | f3f63c1 | 0.11.0-DEV | 1.15.0-DEV.428 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 21.17 | 0.76 | 0.24 | 0.65 | 1.55 | 3.17 | 9.75 |
| 2026-11-05 | 7b0d80e | 0.11.0-DEV | 1.15.0-DEV.476 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 18.4 | 0.7 | 0.21 | 0.57 | 1.33 | 2.87 | 8.48 |
| 2026-11-06 | ddcdf8b | 0.11.0-DEV | 1.15.0-DEV.510 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 24.0 | 0.85 | 0.25 | 0.71 | 1.63 | 3.48 | 10.11 |
| 2026-11-06 | 9812d68 | 0.11.0-DEV | 1.15.0-DEV.542 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 23.28 | 0.83 | 0.25 | 0.67 | 1.64 | 3.47 | 10.09 |
| 2026-11-07 | 9812d68 | 0.11.0-DEV | 1.15.0-DEV.575 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 22.84 | 0.85 | 0.28 | 0.74 | 1.71 | 3.62 | 10.46 |
| 2026-11-08 | b13130d | 0.11.0-DEV | 1.15.0-DEV.594 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 23.13 | 0.83 | 0.25 | 0.67 | 1.64 | 3.52 | 10.21 |
| 2026-11-08 | fe6cc4f | 0.11.0-DEV | 1.15.0-DEV.603 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 23.63 | 0.81 | 0.25 | 0.68 | 1.65 | 3.52 | 10.39 |
| 2026-11-09 | fe6cc4f | 0.11.0-DEV | 1.15.0-DEV.610 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 24.2 | 0.85 | 0.28 | 0.73 | 1.72 | 3.66 | 10.6 |
| 2026-11-10 | 854dacb | 0.11.0-DEV | 1.15.0-DEV.631 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 26.15 | 0.85 | 0.27 | 0.69 | 1.66 | 2.7 | 10.1 |
| 2026-11-11 | 5926f8a | 0.11.0-DEV | 1.15.0-DEV.649 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 435 | 26.77 | 0.88 | 0.27 | 0.72 | 1.65 | 2.72 | 9.89 |

</details>

