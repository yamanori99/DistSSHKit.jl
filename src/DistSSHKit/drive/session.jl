# KitSession — shared context for drive / sync / collect APIs.

"""Runtime context for `sync!`, `size_plan`, `drive!`, `collect!`."""
mutable struct KitSession
    project::String
    hosts::Vector{String}
    remote_root::Union{Nothing,String}
    quiet::Bool
    verbosity::Symbol
    yes::Bool
    include_local_for_size::Bool
    cli_session::KitCliSession
end

"""
    KitSession(; project=pwd(), hosts=[], remote_root=nothing, hosts_file=nothing,
               quiet=false, verbosity=nothing, yes=false, include_local_for_size=false)

Build a session for drive APIs. Host entries may use `host:N` syntax;
worker/slot counts are stripped from `session.hosts` (SSH host names only).
For `go` CLI, `hosts_file` lines keep `host:N` via `read_hosts_file_lines` when
planning slots. Prefer [`WorkerPlan`](@ref) / CLI `host:N` for drive worker counts.

`hosts_file` defaults to `ENV["DISTSSHKIT_HOSTS_FILE"]` when unset.
`verbosity` is `:verbose` | `:progress` | `:quiet` (`quiet=true` implies `:quiet`).
"""
function KitSession(;
    project::AbstractString=pwd(),
    hosts::AbstractVector{<:AbstractString}=String[],
    remote_root::Union{Nothing,AbstractString}=nothing,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=false,
    include_local_for_size::Bool=false,
)
    hf = if hosts_file !== nothing
        String(strip(hosts_file))
    else
        strip(get(ENV, "DISTSSHKIT_HOSTS_FILE", ""))
    end
    cli = KitCliSession(
        quiet=quiet,
        verbosity=verbosity,
        yes=yes,
        hosts_file=isempty(hf) ? nothing : hf,
    )
    host_list = String[]
    for spec in hosts
        h, _ = split_host_workers_spec(String(spec))
        push!(host_list, h)
    end
    append_hosts_file!(host_list, cli)
    proj = canonical_local_path(project)
    rr = remote_root === nothing ? nothing : String(strip(String(remote_root)))
    rr !== nothing && isempty(rr) && (rr = nothing)
    return KitSession(
        proj,
        host_list,
        rr,
        cli.quiet,
        cli.verbosity,
        yes,
        include_local_for_size,
        cli,
    )
end

"""Apply session fields to `ENV` and kit CLI session flags."""
function apply_session_env!(session::KitSession)
    ENV["DISTRIBUTED_PROJECT_ROOT"] = session.project
    if session.remote_root !== nothing
        ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"] = session.remote_root
    end
    session.cli_session.quiet = session.quiet
    session.cli_session.verbosity = session.verbosity
    session.cli_session.yes = session.yes
    apply_kit_cli_session!(session.cli_session)
    return session
end

"""Resolved remote repository root for this session."""
function session_remote_root(session::KitSession)::String
    return resolve_remote_project_root(session.project; cli_override=session.remote_root)
end

"""SSH host names used for [`size_plan`](@ref) (`localhost` first when `include_local_for_size`)."""
function session_size_hosts(session::KitSession)::Tuple{Vector{String},Vector{String}}
    remote = copy(session.hosts)
    if session.include_local_for_size
        return ["localhost"; remote], remote
    end
    return remote, remote
end
