# Cross-cutting user-facing errors: diagnose (facts) then explain (words).
#
# This file owns shared `surface=:cli|:api` helpers and message builders used by
# more than one entry point (drive / go / setup / size / pipeline! / …).
# Domain-specific diagnose/explain pairs stay next to their domain
# (`demos.jl` for demo-install tips, etc.).
#
# See CONTRIBUTING.md ("Errors: diagnose then explain").

"""Normalize explain surface (`:cli` or `:api`)."""
function _normalize_hint_surface(surface::Symbol)::Symbol
    surface === :cli || surface === :api ||
        throw(ArgumentError("hint surface must be :cli or :api, got $(repr(surface))"))
    return surface
end

"""Join a headline with an optional hint line (`nothing` → headline only)."""
join_explained_message(headline::AbstractString, ::Nothing)::String = string(headline)
join_explained_message(headline::AbstractString, hint::AbstractString)::String =
    string(headline, '\n', hint)

# --- script / driver ---------------------------------------------------------

"""
Full script/driver-not-found message (headline + optional demo-related hint).

Used by drive (CLI / `drive!`), go (CLI / `go!`), and [`pipeline!`](@ref).
Demo tip formatting: [`missing_script_demo_hint`](@ref) in `demos.jl`.
"""
function explain_script_not_found(
    script_path::AbstractString,
    project_root::AbstractString;
    surface::Symbol=:cli,
    headline::Union{Nothing,AbstractString}=nothing,
)::String
    path = String(script_path)
    head = headline === nothing ? "Script not found: $path" : String(headline)
    hint = missing_script_demo_hint(path, project_root; surface=surface)
    return join_explained_message(head, hint)
end

"""Missing `DRIVER=` / `driver=` for [`pipeline_config_from_env`](@ref)."""
function explain_pipeline_driver_missing(; surface::Symbol=:api)::String
    surface = _normalize_hint_surface(surface)
    if surface === :cli
        return "set DRIVER=path/to/driver.jl (or pass a driver path to the pipeline entry)"
    end
    return "set DRIVER=path/to/driver.jl or pass driver= keyword"
end

# --- hosts file / SSH hosts --------------------------------------------------

function explain_hosts_file_not_found(
    path::AbstractString;
    surface::Symbol=:cli,
)::String
    surface = _normalize_hint_surface(surface)
    p = String(path)
    head = "hosts file not found: $p"
    hint = if surface === :api
        "Hint: pass hosts_file=\"…\" to KitSession / go!, or set ENV[\"DISTSSHKIT_HOSTS_FILE\"]"
    else
        "Hint: pass --hosts-file PATH, or set DISTSSHKIT_HOSTS_FILE"
    end
    return join_explained_message(head, hint)
end

function explain_hosts_file_empty(
    path::AbstractString;
    surface::Symbol=:cli,
)::String
    surface = _normalize_hint_surface(surface)
    p = String(path)
    head = "hosts file has no hosts: $p"
    hint = if surface === :api
        "Hint: add host lines (or host:N), or pass workers=[…] instead"
    else
        "Hint: add host lines (or host:N), or pass hosts on the command line"
    end
    return join_explained_message(head, hint)
end

"""
No SSH / size hosts on a session.

`kind` is `:ssh` (sync/setup/instantiate), `:collect`, or `:size`.
"""
function explain_no_hosts(;
    surface::Symbol=:api,
    kind::Symbol=:ssh,
)::String
    surface = _normalize_hint_surface(surface)
    kind in (:ssh, :collect, :size) ||
        throw(ArgumentError("explain_no_hosts kind must be :ssh, :collect, or :size"))
    if kind === :size
        head = "KitSession has no hosts for size!"
        hint = if surface === :api
            "Hint: pass workers=[\"parent:2\", …] or workers=[\"child:user@host\", …] (omit :N → autosize)"
        else
            "Hint: pass local and/or SSH hosts (see size --help)"
        end
        return join_explained_message(head, hint)
    elseif kind === :collect
        head = "collect! needs hosts in session or hosts= keyword"
        hint = if surface === :api
            "Hint: KitSession(workers=[\"child:user@host\", …]) or collect!(…; hosts=[…])"
        else
            "Hint: pass HOST after --collect-missing / --collect-overwrite ROOT"
        end
        return join_explained_message(head, hint)
    end
    head = "KitSession has no SSH hosts"
    hint = if surface === :api
        "Hint: pass workers= with child:NAME tokens, or hosts_file="
    else
        "Hint: pass child:NAME tokens, or --hosts-file / DISTSSHKIT_HOSTS_FILE"
    end
    return join_explained_message(head, hint)
end

# --- local host tools (ssh / rsync / git) ------------------------------------

const _HOST_TOOL_NAMES = ("ssh", "rsync", "git")

function _normalize_host_tool(name::AbstractString)::String
    n = String(name)
    n == "ssh" || n == "scp" || n == "rsync" || n == "git" ||
        throw(ArgumentError("host tool must be ssh, scp, rsync, or git, got $(repr(n))"))
    return n
end

"""Hint line when `ssh` / `rsync` / `git` is absent from `PATH`."""
function explain_host_tool_hint(tool::AbstractString; surface::Symbol=:api)::String
    _normalize_hint_surface(surface)
    t = _normalize_host_tool(tool)
    t == "ssh" && return "Hint: DistSSHKit does not install OpenSSH; see Requirements"
    t == "scp" && return "Hint: DistSSHKit does not install OpenSSH (scp); see Requirements"
    t == "rsync" &&
        return "Hint: DistSSHKit does not install rsync; needed for collect and setup --rsync (see Requirements)"
    return "Hint: DistSSHKit does not install git; needed for clone / push / pull (see Requirements)"
end

"""Full message when a required host tool is not on `PATH`."""
function explain_host_tool_missing(tool::AbstractString; surface::Symbol=:api)::String
    t = _normalize_host_tool(tool)
    return join_explained_message("$t not found in PATH", explain_host_tool_hint(t; surface=surface))
end

# --- setup / clone -----------------------------------------------------------

function explain_clone_repo_required(; surface::Symbol=:api)::String
    surface = _normalize_hint_surface(surface)
    if surface === :api
        return "setup!(session, :clone) requires repo=\"git-url\" " *
               "(no silent origin lookup; clone runs on the remote)"
    end
    return "setup --clone requires --repo URL " *
           "(no silent origin lookup; clone runs on the remote)"
end

function explain_clone_origin_missing(; surface::Symbol=:cli)::String
    surface = _normalize_hint_surface(surface)
    if surface === :api
        return "Could not read git remote `origin`; pass repo=\"git-url\" to setup!(…, :clone)"
    end
    return "Could not read git remote `origin`; pass --repo URL"
end

# --- size probe --------------------------------------------------------------

function explain_size_probe_not_found(
    path::AbstractString;
    surface::Symbol=:api,
)::String
    surface = _normalize_hint_surface(surface)
    p = String(path)
    head = "size probe not found: $p"
    hint = if surface === :api
        "Hint: pass probe=\"relative/or/absolute.jl\" under the project, or omit probe="
    else
        "Hint: pass --probe PATH under the project, or omit --probe"
    end
    return join_explained_message(head, hint)
end
