# collect! — pull result trees from remotes (same core as `drive --collect-*`).

"""
    collect!(
        session::KitSession,
        local_root::AbstractString;
        merge=false,
        hosts=nothing,
    )

Rsync result files from SSH hosts into `local_root`.

Collect modes:
- `merge=false` → **collect-missing** (CLI `drive --collect-missing`)
- `merge=true` → **collect-overwrite** (CLI `drive --collect-overwrite`)

Distinct from drive's automatic **post-run-new** (sentinel / newer-than-run) and go's
**slot-overwrite**. Returns [`CollectResult`](@ref).
"""
function collect!(
    session::KitSession,
    local_root::AbstractString;
    merge::Bool=false,
    hosts::Union{Nothing,AbstractVector{<:AbstractString}}=nothing,
)::CollectResult
    apply_session_env!(session)
    host_list = hosts === nothing ? session.hosts : collect(String, hosts)
    isempty(host_list) && throw(ArgumentError("collect! needs hosts in session or hosts= keyword"))
    _ensure_drive_fragments!(session.project)
    collect_fn = Main.eval(:(drive_collect_tree))
    ok = Base.invokelatest(
        collect_fn,
        String(local_root),
        host_list;
        merge=merge,
    )
    return CollectResult(ok, ok ? 0 : 1)
end
