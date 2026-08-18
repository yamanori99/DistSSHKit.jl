# sync! — rsync or git sync via shared DistSSHKit cores (not CLI argv).

"""
    sync!(session::KitSession; mode=:sync)

Sync local project to SSH hosts (call explicitly; go/drive do not call this by default).

- `mode=:sync` — git push + pull on remotes (confirm unless `session.yes`)
- `mode=:rsync` — rsync working tree (no git; confirm unless `session.yes`).
  Refuses nonempty remote paths; use `setup!(session, :delete)` /
  `setup --delete` first.

Also available as `setup!(session, :rsync)` / `setup!(session, :sync)`.

Returns [`SyncResult`](@ref).
"""
function sync!(session::KitSession; mode::Union{Symbol,Bool}=:sync)::SyncResult
    mode === false && throw(ArgumentError("sync!: mode=false means skip sync; do not call sync!"))
    apply_session_env!(session)
    isempty(session.hosts) && throw(ArgumentError(
        explain_no_hosts(; surface=hint_surface(session), kind=:ssh),
    ))
    remote_path = session_remote_root(session)

    if mode === :rsync
        raw = rsync_project_to_hosts!(
            session.hosts,
            session.project,
            remote_path;
            confirm=!session.yes,
            path_anchor=session.project,
        )
        if raw.cancelled
            return SyncResult(true, HostResult[]; ok=false)
        end
        return SyncResult(false, raw.host_results; ok=raw.failed == 0)
    elseif mode === :sync
        raw = git_sync_project_to_hosts!(
            session.hosts,
            session.project,
            remote_path;
            do_push=true,
            do_pull=true,
            do_local_pull=false,
            confirm=!session.yes,
        )
        if raw.cancelled
            return SyncResult(true, HostResult[]; ok=false)
        end
        return SyncResult(false, raw.host_results; ok=raw.ok)
    else
        throw(ArgumentError("sync! mode must be :rsync or :sync, got $(repr(mode))"))
    end
end
