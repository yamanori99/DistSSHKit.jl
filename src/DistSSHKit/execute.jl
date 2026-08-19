# execute! — one seam over `go!` / `drive!` for callers that pick the kind at runtime
# (the queue layer; see https://github.com/yamanori99/DistSSHKit.jl/issues/129).
# Thin wrapper only: `go!` / `drive!` / `src/cli/*` are untouched.

"""
    execute!(kind, script, tokens=String[]; output_dir=nothing, args=String[], project=pwd(), sync=nothing, julia=nothing, kwargs...) -> KitRunResult

One seam over [`go!`](@ref) / [`drive!`](@ref) for callers that pick the kind
at runtime (`kind ∈ (:go, :drive)`), returning the shared [`KitRunResult`](@ref)
instead of `GoResult` / `DriveResult`.

```julia
execute!(:go, "job.jl", ["local:2"]; args=["8"])
execute!(:drive, "job.jl", ["local:2"]; args=["8"])
```

`output_dir`, `args`, `project`, `sync`, `julia` are the keywords [`go!`](@ref)
and [`drive!`](@ref) already share. Any other keyword (`remote`, `hosts_file`,
`quiet`, `verbosity`, `yes`, `collect_spec`, `path_anchor`, `skip_hash_check`,
`require_all_hosts`, `plan`, …) is forwarded verbatim to the chosen function —
`execute!` does not re-declare or validate kind-specific keywords.
"""
function execute!(
    kind::Symbol,
    script::AbstractString,
    tokens::AbstractVector{<:AbstractString}=String[];
    output_dir::Union{Nothing,AbstractString}=nothing,
    args::AbstractVector{<:AbstractString}=String[],
    project::AbstractString=pwd(),
    sync::Union{Symbol,Bool,Nothing}=nothing,
    julia::Union{Nothing,AbstractString}=nothing,
    kwargs...,
)::KitRunResult
    kind in (:go, :drive) || throw(ArgumentError("execute! kind must be :go or :drive, got $(repr(kind))"))
    result = if kind === :go
        go!(
            script,
            tokens;
            output_dir=output_dir,
            args=args,
            project=project,
            sync=sync,
            julia=julia,
            kwargs...,
        )
    else
        drive!(
            script,
            tokens;
            output_dir=output_dir,
            args=args,
            project=project,
            sync=sync,
            julia=julia,
            kwargs...,
        )
    end
    return kit_run_result(result)
end
