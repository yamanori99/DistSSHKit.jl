using Distributed

"""
    resolve_distributed_output_dir!(script_args, default_dir)

Set `ENV["DISTRIBUTED_OUTPUT_DIR"]` for a driver run and return the canonical path.

Priority (first match wins):

1. `ENV["DISTRIBUTED_OUTPUT_DIR"]` if already set (drive `--output-dir`, operator `export`, …)
2. `--output-dir PATH` in `script_args`
3. `default_dir` (e.g. `joinpath(@__DIR__, "output")`)

Creates the directory when missing. Drivers should call this from `init_output_dir!`.
"""
function resolve_distributed_output_dir!(
    script_args::Vector{String},
    default_dir::AbstractString,
)::String
    existing = strip(get(ENV, "DISTRIBUTED_OUTPUT_DIR", ""))
    if !isempty(existing)
        dir = canonical_local_path(existing)
        mkpath(dir)
        ENV["DISTRIBUTED_OUTPUT_DIR"] = dir
        return dir
    end
    for j in 1:length(script_args) - 1
        if script_args[j] == "--output-dir"
            dir = canonical_local_path(script_args[j + 1])
            mkpath(dir)
            ENV["DISTRIBUTED_OUTPUT_DIR"] = dir
            return dir
        end
    end
    dir = canonical_local_path(default_dir)
    mkpath(dir)
    ENV["DISTRIBUTED_OUTPUT_DIR"] = dir
    return dir
end

"""
    worker_pmap(f, collection)

Like `Distributed.pmap`, but evaluates `f` with `Base.invokelatest` on each element.

After `drive` syncs your driver to workers and loads the project package, plain
`pmap` is usually enough. Use `worker_pmap` when a callback still hits Julia 1.12+
world-age errors (for example, a function reference or closure captured before
package load).
"""
worker_pmap(f, collection) = pmap(x -> Base.invokelatest(f, x), collection)
