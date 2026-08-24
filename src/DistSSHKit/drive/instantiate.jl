# instantiate! — Pkg.instantiate on remotes (same core as `setup --instantiate`).

"""
    instantiate!(session::KitSession; julia="auto") -> SyncResult

Run `Pkg.instantiate()` on each SSH host in `session` (parallel).

`julia` is the remote Julia path (`"auto"` detects per host, same as
`setup --instantiate` / `drive --julia`). Returns [`SyncResult`](@ref).

Typical first-time remote prep:

```julia
session = KitSession(workers=["child:user@h1"], remote="/path/to/project", yes=true)
setup!(session, :delete, :rsync, :instantiate)  # or sync!(…; mode=:rsync) then instantiate!
```

Also available as [`setup!`](@ref)`(session, :instantiate; julia=…)`.
"""
function instantiate!(
    session::KitSession;
    julia::AbstractString="auto",
)::SyncResult
    apply_session_env!(session)
    isempty(session.hosts) && throw(ArgumentError(
        explain_no_hosts(; surface=hint_surface(session), kind=:ssh),
    ))
    validate_setup_hosts(session.hosts)
    preflight_setup_ssh(session.hosts) || return SyncResult(
        true,
        HostResult[];
        ok=false,
    )
    remote_path = session_remote_root(session)
    julia_path = isempty(strip(String(julia))) ? "auto" : String(julia)
    raw = instantiate_remotes(
        session.hosts,
        julia_path,
        remote_path,
        session.project;
        path_anchor=session.project,
    )
    hrs = hasproperty(raw, :hosts) ? collect(HostResult, raw.hosts) : HostResult[]
    return SyncResult(
        raw.cancelled,
        hrs;
        ok=!raw.cancelled && raw.failed == 0,
    )
end
