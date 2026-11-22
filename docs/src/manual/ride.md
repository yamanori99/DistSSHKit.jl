# [ride](@id Manual-ride)

Experimental. Run a **plain** script (`map` / `filter` / simple
comprehensions / independent indexed `for`). DistSSHKit rewrites those forms and
may `pmap` them on Distributed workers (head and SSH remotes).

```bash
julia --project=. -m DistSSHKit ride --head-workers 2 SCRIPT.jl
julia --project=. -m DistSSHKit ride --head-workers 1 2*host1 SCRIPT.jl
```

Listed machine tokens need an explicit count (`N*host`; bare host = 1 worker).
Head workers default to 0 until `--head-workers` or tokens. SSH remotes use the same
worker-add path as [`drive`](@ref Manual-drive).
Prepare remotes with [`setup`](@ref Manual-setup) first. Distributed
vocabulary (`pmap`, `@everywhere`, …) is an error; that script belongs on
`drive`. Listed remote hosts are fail-closed.

`for i in iter; dest[i] = expr; end` is rewritten when `expr` does not
read `dest`, does not `return` / `break` / `continue`, and every index in
`expr` is `i` (so `dest[i] = alias[i - 1]` stays sequential). If runtime
effect analysis rejects distribution, or `dest` may alias an array the
RHS captures (including nested in a struct), or a `Main` array aliases
`dest` (including `const` globals the closure does not capture), or
`iterate` on the loop iterator is not effect-free, the iterator is not
collected first;
each `dest[i] = expr` runs in order. Distributed fills collect then map.
SPI compares mapped RHS values before `dest` writes, so it does not catch
that aliasing; the runtime overlap check does (including fail-closed if
the capture walk hits its depth limit).
Broadcast, `reduce`, and accumulating `for` stay out of scope.

`--spi-check` is **off** by default. Pass it to also run each rewritten
`map` / `filter` (including values from indexed `for`) sequentially and
compare. `--no-spi-check` is an explicit skip. Under `--progress`, a
successful compare prints `SPI check: passed` after the script stdout.
With the compare off, or when the script stayed sequential, that line is
`SPI check: skipped (sequential or off)`.

ride distributes only what the compiler can prove safe. The guarantee
follows from the discussion in
[JuliaLang/julia#43910](https://github.com/JuliaLang/julia/issues/43910):
if `f` and `getindex` are `:effect_free`, parallel map does not introduce
new data races. Thread-parallel POC and this SSH/process `ride` are not
the same implementation.

Default artifacts: `{script}/.distsshkit/ride/{stem}_{UTC}/`. Sidecars
(`run.toml`, pid, stdio): `{script}/.distsshkit/runs/ride/{stem}_{UTC}/`
(same project / `tempdir()` fallbacks as go when the script dir is not
writable).

DistSSHRun removed the `ride` CLI and `ride!`; use [`drive`](@ref Manual-drive)
with `pmap` instead. Queue `submit` may still accept `:ride` until the next
Queue lockstep; [`execute!`](@ref) (`:ride`, including `detached=true`) follows
Queue until then.
