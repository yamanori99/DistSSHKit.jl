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

- 1.13: julia 1.13.2 -> 1.13.3
- 1.13: status method 594.2 ms -> 2070.8 ms: Tuple{typeof(DistSSHQueue.main), Array{String, 1}}
- 1.14-nightly: julia 1.14.0-alpha1.112 -> 1.14.0-alpha2
- 1.14-nightly: status method 347.6 ms -> 2889.6 ms: Tuple{typeof(DistSSHQueue.main), Array{String, 1}}
- nightly: julia 1.15.0-DEV.132 -> 1.15.0-DEV.152
- nightly: status method 293.0 ms -> 3004.3 ms: Tuple{typeof(DistSSHQueue.main), Array{String, 1}}
- nightly: drive method 137.6 ms -> 302.1 ms: Tuple{typeof(Base.print), Base.PipeEndpoint, Array{Int64, 1}, String}
- nightly: drive method 127.7 ms -> 277.0 ms: Tuple{typeof(Distributed.read_worker_host_port), Base.PipeEndpoint}

<details open>
<summary>1.13</summary>

| date | commit | version | julia | os | arch | src files | code lines | full s | pkg s | using s | help s | status s | go s | drive s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-18 | be54052 | 0.10.2 | 1.13.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 410 | 6.13 | 0.8 | 0.25 | 0.63 | 11.52 | 6.25 | 22.36 |
| 2026-10-19 | 72e0a48 | 0.10.2 | 1.13.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 410 | 9.34 | 1.05 | 0.32 | 0.82 | 14.84 | 7.81 | 27.68 |
| 2026-10-20 | b02f4dd | 0.10.2 | 1.13.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 9.02 | 1.0 | 0.33 | 0.82 | 6.08 | 7.69 | 27.25 |
| 2026-10-20 | d1bb1de | 0.10.3 | 1.13.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 10.09 | 1.07 | 0.34 | 0.9 | 6.37 | 8.08 | 28.14 |
| 2026-10-20 | 33ecf3a | 0.10.3 | 1.13.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 6.1 | 0.74 | 0.22 | 0.6 | 3.95 | 5.11 | 19.16 |
| 2026-10-21 | 0d024d1 | 0.10.3 | 1.13.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 7.11 | 0.8 | 0.26 | 0.7 | 4.91 | 6.33 | 22.37 |
| 2026-10-22 | 2e838fd | 0.10.4 | 1.13.2 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 415 | 7.84 | 0.91 | 0.29 | 0.73 | 5.27 | 6.73 | 23.75 |
| 2026-10-23 | 2e838fd | 0.10.4 | 1.13.2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 6.72 | 0.79 | 0.25 | 0.64 | 4.57 | 6.55 | 21.03 |
| 2026-10-24 | ac1ce0f | 0.10.5 | 1.13.2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 10.21 | 1.07 | 0.35 | 0.88 | 6.63 | 9.43 | 29.2 |
| 2026-10-24 | 7edf0c1 | 0.10.5 | 1.13.2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 10.37 | 1.12 | 0.35 | 0.89 | 6.85 | 9.8 | 30.15 |
| 2026-10-25 | f610f7c | 0.10.6 | 1.13.2 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 11.21 | 1.22 | 0.39 | 1.23 | 7.84 | 11.21 | 34.26 |
| 2026-10-26 | 399faf6 | 0.10.6 | 1.13.3 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 6.43 | 0.75 | 0.24 | 0.78 | 5.34 | 6.6 | 21.47 |

</details>

<details>
<summary>1.14-nightly</summary>

| date | commit | version | julia | os | arch | src files | code lines | full s | pkg s | using s | help s | status s | go s | drive s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-18 | be54052 | 0.10.2 | 1.14.0-DEV.3787 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 410 | 7.48 | 0.88 | 0.34 | 0.64 | 6.63 | 3.29 | 12.38 |
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

</details>

<details>
<summary>nightly</summary>

| date | commit | version | julia | os | arch | src files | code lines | full s | pkg s | using s | help s | status s | go s | drive s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-18 | be54052 | 0.10.2 | 1.14.0-DEV.3787 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 410 | 5.15 | 0.68 | 0.23 | 0.44 | 4.22 | 2.12 | 8.76 |
| 2026-10-19 | 72e0a48 | 0.10.2 | 1.15.0-DEV.18 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 410 | 5.95 | 0.71 | 0.26 | 0.5 | 4.81 | 2.51 | 9.99 |
| 2026-10-20 | b02f4dd | 0.10.2 | 1.15.0-DEV.29 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 7.19 | 0.76 | 0.31 | 0.58 | 1.76 | 2.97 | 11.09 |
| 2026-10-20 | d1bb1de | 0.10.3 | 1.15.0-DEV.29 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 8.01 | 0.84 | 0.35 | 0.64 | 1.95 | 3.32 | 12.28 |
| 2026-10-20 | 33ecf3a | 0.10.3 | 1.15.0-DEV.53 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 5.62 | 0.66 | 0.23 | 0.47 | 1.37 | 2.27 | 9.49 |
| 2026-10-21 | 0d024d1 | 0.10.3 | 1.15.0-DEV.71 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 402 | 9.29 | 0.99 | 0.36 | 0.67 | 2.14 | 3.65 | 13.69 |
| 2026-10-22 | 2e838fd | 0.10.4 | 1.15.0-DEV.84 | Ubuntu 24.04.5 LTS | x86_64 | 1 | 415 | 8.83 | 0.89 | 0.3 | 0.61 | 2.0 | 3.41 | 12.99 |
| 2026-10-23 | 2e838fd | 0.10.4 | 1.15.0-DEV.104 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 8.3 | 0.9 | 0.32 | 0.61 | 2.08 | 3.96 | 13.27 |
| 2026-10-24 | ac1ce0f | 0.10.5 | 1.15.0-DEV.109 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 7.47 | 0.83 | 0.26 | 0.53 | 1.82 | 3.44 | 11.8 |
| 2026-10-24 | 7edf0c1 | 0.10.5 | 1.15.0-DEV.126 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 415 | 9.33 | 0.92 | 0.31 | 0.63 | 2.14 | 4.07 | 13.43 |
| 2026-10-25 | f610f7c | 0.10.6 | 1.15.0-DEV.132 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 434 | 7.01 | 0.71 | 0.2 | 0.55 | 1.71 | 3.22 | 11.29 |
| 2026-10-26 | 399faf6 | 0.10.6 | 1.15.0-DEV.152 | Ubuntu 26.04.1 LTS | x86_64 | 1 | 437 | 9.39 | 0.86 | 0.24 | 0.67 | 2.55 | 4.06 | 13.36 |

</details>

