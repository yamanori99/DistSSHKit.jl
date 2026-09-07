# [ride](@id Manual-ride)

Experimental. Run a **plain** script (`map` / `filter` / simple
comprehensions / independent indexed `for`). Kit rewrites those forms and
may `pmap` them on Distributed workers (parent and SSH `child:`). Inspect
first with [`plan`](@ref).

```bash
julia --project=. -m DistSSHKit plan SCRIPT.jl
julia --project=. -m DistSSHKit ride parent:2 SCRIPT.jl
julia --project=. -m DistSSHKit ride parent:1 child:host1:2 SCRIPT.jl
```

SSH children use the same worker-add path as [`drive`](@ref Manual-drive).
Prepare remotes with [`setup`](@ref Manual-setup) first. Distributed
vocabulary (`pmap`, `@everywhere`, …) is an error; that script belongs on
`drive`. Listed `child:` hosts are fail-closed.

`for i in iter; dest[i] = expr; end` is rewritten when `expr` does not
read `dest`, does not `return` / `break` / `continue`, and every index in
`expr` is `i` (so `dest[i] = alias[i - 1]` stays sequential). If runtime
effect analysis rejects distribution, or `dest` may alias an array the
RHS captures (overlapping `@view`s), the iterator is not collected first;
each `dest[i] = expr` runs in order. Distributed fills collect then map.
SPI compares mapped RHS values before `dest` writes, so it does not catch
that aliasing; the runtime overlap check does.
Broadcast, `reduce`, and accumulating `for` stay out of scope.

`--spi-check` is **on** by default: each rewritten `map` / `filter` (including
values from indexed `for`) is also run sequentially and compared. `--no-spi-check` skips that. Under
`--progress`, a successful run prints `SPI check: passed` after the script
stdout.

ride distributes only what the compiler can prove safe. The guarantee
follows from the discussion in
[JuliaLang/julia#43910](https://github.com/JuliaLang/julia/issues/43910):
if `f` and `getindex` are `:effect_free`, parallel map does not introduce
new data races. Thread-parallel POC and this SSH/process `ride` are not
the same implementation.

Also: `ride --help`. API: [`ride!`](@ref), [`execute!`](@ref) (`:ride`, including
`detached=true` for DistSSHQueue).
