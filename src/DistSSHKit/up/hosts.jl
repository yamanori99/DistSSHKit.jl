# add / update / default on `parent` and on a child SSH host.
# Confirm text and progress stay in DistSSHRun.

function _juliaup_remote_capture(host::AbstractString, script::AbstractString)
    out_buf = IOBuffer()
    err_buf = IOBuffer()
    proc = run(
        pipeline(
            ignorestatus(_host_sync_remote_shell_cmd(String(host), String(script)));
            stdout = out_buf,
            stderr = err_buf,
        );
        wait = true,
    )
    out_s = strip(String(take!(out_buf)))
    err_s = strip(String(take!(err_buf)))
    if proc.exitcode != 0
        msg = err_s
        isempty(msg) && (msg = out_s)
        isempty(msg) && (msg = "exit $(proc.exitcode)")
        error(first(split(msg, '\n')))
    end
    return out_s
end

"""
`juliaup add` / `update` / `default` for one target.

`parent` is this machine. Anything else is an SSH host. Returns
`(host, channel, already, ver)`. `ver` is `nothing` when a child was already
on the channel.
"""
function juliaup_align_host!(
        host::AbstractString;
        channel::AbstractString = juliaup_channel(),
    )
    h = String(host)
    ch = String(channel)
    if is_parent_host_name(h)
        r = juliaup_align_local!(ch)
        return (;
            host = PARENT_HOST_NAME,
            channel = ch,
            already = !r.changed,
            ver = r.ver,
        )
    end
    out = _juliaup_remote_capture(h, _juliaup_align_remote_sh(ch))
    if out == "already"
        return (; host = h, channel = ch, already = true, ver = nothing)
    end
    clear_detect_julia_path_cache!(h)
    path = detect_julia_path(h)
    path === nothing && error("Julia not found after juliaup align")
    ver = _remote_julia_version_setup_ssh(h, path)
    ver === nothing && error("Julia --version unparseable after juliaup align")
    if julia_version_mismatch_kind(VERSION, ver) == :minor
        error("still mismatched after align: process $(VERSION), remote $ver")
    end
    return (; host = h, channel = ch, already = false, ver = ver)
end

"""Installed patch of the juliaup default on `host`, or `-`.

`parent` is this machine. Anything else is an SSH host. Missing juliaup, a
failed `status`, or no Version column is `-`.
"""
function juliaup_default_patch(host::AbstractString)::String
    h = String(host)
    if is_parent_host_name(h)
        ju = find_local_juliaup()
        ju === nothing && return "-"
        proc, out, _ = _juliaup_run_captured(ju, ["status"])
        Int(something(proc.exitcode, 1)) == 0 || return "-"
        return _juliaup_patch_from_status(out)
    end
    try
        out_buf = IOBuffer()
        proc = run(
            pipeline(
                ignorestatus(_host_sync_remote_shell_cmd(h, _juliaup_status_sh()));
                stdout = out_buf,
                stderr = devnull,
            );
            wait = true,
        )
        Int(something(proc.exitcode, 1)) == 0 || return "-"
        return _juliaup_patch_from_status(String(take!(out_buf)))
    catch
        return "-"
    end
end

"""`juliaup update` on `parent` or one SSH host. Does not change the default.

`channel === nothing` updates every installed channel. A channel updates that one.
"""
function juliaup_update_host!(
        host::AbstractString;
        channel::Union{Nothing, AbstractString} = nothing,
    )
    h = String(host)
    ch = channel === nothing ? nothing : String(channel)
    if is_parent_host_name(h)
        if ch === nothing
            juliaup_update_local!()
        else
            juliaup_update_local!(ch)
        end
        return (; host = PARENT_HOST_NAME)
    end
    script = ch === nothing ? _juliaup_update_remote_sh() : _juliaup_update_channel_remote_sh(ch)
    _juliaup_remote_capture(h, script)
    return (; host = h)
end

"""`juliaup add` on `parent` or one SSH host. Does not change the default."""
function juliaup_add_host!(host::AbstractString, channel::AbstractString)
    h = String(host)
    ch = String(channel)
    if is_parent_host_name(h)
        juliaup_add_local!(ch)
        return (; host = PARENT_HOST_NAME, channel = ch)
    end
    _juliaup_remote_capture(h, _juliaup_add_remote_sh(ch))
    return (; host = h, channel = ch)
end

"""`juliaup default` on `parent` or one SSH host.

A missing channel fails. Success drops the cached Julia path for that host,
so the next lookup sees the new default.
"""
function juliaup_default_host!(host::AbstractString, channel::AbstractString)
    h = String(host)
    ch = String(channel)
    if is_parent_host_name(h)
        juliaup_default_local!(ch)
        clear_detect_julia_path_cache!(PARENT_HOST_NAME)
        return (; host = PARENT_HOST_NAME, channel = ch)
    end
    _juliaup_remote_capture(h, _juliaup_default_remote_sh(ch))
    clear_detect_julia_path_cache!(h)
    return (; host = h, channel = ch)
end

"""Installed `juliaup status` rows on `host`. Optional `channel` keeps that row."""
function juliaup_status_lines(
        host::AbstractString;
        channel::Union{Nothing, AbstractString} = nothing,
    )::Vector{String}
    h = String(host)
    ch = channel === nothing ? nothing : String(channel)
    if is_parent_host_name(h)
        ju = find_local_juliaup()
        ju === nothing && return String[]
        proc, out, _ = _juliaup_run_captured(ju, ["status"])
        Int(something(proc.exitcode, 1)) == 0 || return String[]
        return _installed_status_lines(out; channel = ch)
    end
    try
        out = _juliaup_remote_capture(h, _juliaup_status_sh())
        return _installed_status_lines(out; channel = ch)
    catch
        return String[]
    end
end
