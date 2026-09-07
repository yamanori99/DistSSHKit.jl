# Push content-hash cache blobs over SSH (project rsync excludes `.distsshkit/`).

"""
    cache_remote_dir(remote_root) -> String

Join `remote_root` with `.distsshkit/cache/sha256` (same layout as local
[`cache_relpath`](@ref)).
"""
function cache_remote_dir(remote_root::AbstractString)::String
    return joinpath(String(remote_root), _NS_CACHE_DIR)
end

function _cache_blob_names(
        local_dir::AbstractString,
        hashes::Union{Nothing, AbstractVector{<:AbstractString}},
    )::Vector{String}
    names = if hashes === nothing
        isdir(local_dir) || return String[]
        String[n for n in readdir(local_dir) if length(n) == 64 && all(isxdigit, n)]
    else
        String[lowercase(strip(String(h))) for h in hashes]
    end
    for n in names
        cache_relpath(n)
        isfile(joinpath(local_dir, n)) || throw(
            ArgumentError(
                "push_cache!: missing local blob $(joinpath(local_dir, n))",
            )
        )
    end
    return names
end

function _rsync_cache_one_host!(
        host::AbstractString,
        local_dir::AbstractString,
        remote_dir::AbstractString,
        files::Vector{String},
    )::HostResult
    h = String(host)
    if !_ensure_remote_dir(h, remote_dir)
        return HostResult(h, false, "could not create remote cache directory")
    end
    transport = _host_sync_rsync_transport()
    rsync = _host_sync_rsync_argv()
    src = local_dir * "/"
    dest = string(h, ":", rstrip(remote_dir, '/'), "/")
    opts = String["-az", "-e", transport]
    try
        _run_rsync_files_from(rsync, opts, src, dest, files; stderr = stderr)
        return HostResult(h, true, "cache rsync ok")
    catch e
        _rethrow_missing_host_tool(e)
        return HostResult(h, false, sprint(showerror, e))
    end
end

"""
    push_cache!(session; hashes=nothing) -> SyncResult

Rsync local `.distsshkit/cache/sha256/` blobs onto each SSH host under the
same relative path on the session remote project root. Does not use `--delete`.
Project `setup --rsync` still excludes `.distsshkit/`; this call is the
dedicated transfer.

`hashes` limits the push to those digests. `nothing` pushes every local blob.
No SSH hosts → error. Empty cache → success with no host rows.
"""
function push_cache!(
        session::KitSession;
        hashes::Union{Nothing, AbstractVector{<:AbstractString}} = nothing,
    )::SyncResult
    isempty(session.hosts) && throw(
        ArgumentError(
            explain_no_hosts(; surface = hint_surface(session), kind = :ssh),
        )
    )
    return _with_kit_inproc_run!(:sync) do
        apply_session_env!(session)
        local_dir = joinpath(session.project, _NS_CACHE_DIR)
        files = _cache_blob_names(local_dir, hashes)
        isempty(files) && return SyncResult(false, HostResult[]; ok = true)
        remote_dir = cache_remote_dir(session_remote_root(session))
        results = HostResult[]
        for host in session.hosts
            push!(results, _rsync_cache_one_host!(host, local_dir, remote_dir, files))
        end
        return SyncResult(false, results; ok = all(r -> r.ok, results))
    end
end
