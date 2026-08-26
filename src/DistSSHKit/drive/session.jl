# KitSession — shared context for drive / sync / collect APIs.

"""Runtime context for `sync!`, `size!`, `drive!`, `collect!`."""
mutable struct KitSession
    project::String
    hosts::Vector{String}
    tokens::Vector{String}
    remote::Union{Nothing,String}
    quiet::Bool
    verbosity::Symbol
    yes::Bool
    include_parent_for_size::Bool
    cli_session::KitCliSession
end

"""
    KitSession(; project=pwd(), workers=[], remote=nothing, hosts_file=nothing,
               quiet=false, verbosity=nothing, yes=true, include_parent_for_size=false)

Build a session for drive APIs. `workers` are CLI-style tokens
(`parent:2`, `child:user@host:1`). Omitted `:N` is filled by `-w` or [`size!`](@ref).

`session.hosts` keeps remote SSH names only (for sync / collect).
`session.tokens` keeps the original tokens (including `parent:N`).
`remote` is the remote project path (`DISTRIBUTED_REMOTE_PROJECT_ROOT`).

`hosts_file` is appended when given. `ENV["DISTSSHKIT_HOSTS_FILE"]` is used
only when `hosts_file` is omitted **and** `workers` is empty (same as
[`go!`](@ref)). Non-empty `workers` do not re-read that ENV.
`verbosity` is `:verbose` | `:progress` | `:quiet` (`quiet=true` implies `:quiet`).
API default `yes=true` skips confirm prompts.
"""
function KitSession(;
    project::AbstractString=pwd(),
    workers::AbstractVector{<:AbstractString}=String[],
    remote::Union{Nothing,AbstractString}=nothing,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=true,
    include_parent_for_size::Bool=false,
)
    tokens = String[String(h) for h in workers]
    hf = if hosts_file !== nothing
        String(strip(hosts_file))
    elseif isempty(tokens)
        strip(get(ENV, "DISTSSHKIT_HOSTS_FILE", ""))
    else
        ""
    end
    hf_path = isempty(hf) ? nothing : hf
    cli = KitCliSession(
        quiet=quiet,
        verbosity=verbosity,
        yes=yes,
        hosts_file=hf_path,
        hint_surface=:api,
    )
    tokens = String[String(h) for h in workers]
    if hf_path !== nothing
        for line in read_hosts_file_lines(hf_path; surface=:api)
            push!(tokens, line)
        end
    end
    parsed = parse_worker_tokens(tokens)
    include_parent = include_parent_for_size || parsed.parent_autosize
    proj = canonical_local_path(project)
    rr = remote === nothing ? nothing : String(strip(String(remote)))
    rr !== nothing && isempty(rr) && (rr = nothing)
    return KitSession(
        proj,
        copy(parsed.child_hosts),
        parsed.tokens,
        rr,
        cli.quiet,
        cli.verbosity,
        yes,
        include_parent,
        cli,
    )
end

"""Apply session fields to `ENV` and kit CLI session flags."""
function apply_session_env!(session::KitSession)
    ENV["DISTRIBUTED_PROJECT_ROOT"] = session.project
    if session.remote !== nothing
        rr = strip(String(session.remote))
        isempty(rr) || (ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"] = remote_env_project_root(rr))
    end
    session.cli_session.quiet = session.quiet
    session.cli_session.yes = session.yes
    # Non-explicit sessions auto-resolve to `:verbose` when stdout is a pipe
    # (Pkg.test). Do not wipe an ambient `:progress` / `:quiet` pin — that
    # flipped `writeln_field("Log file", …)` back on under `setup!` (#238).
    if !(session.cli_session.verbosity_explicit || session.quiet)
        ambient = kit_verbosity()
        if ambient in (:progress, :quiet) && session.verbosity === :verbose
            session.verbosity = ambient
            session.quiet = ambient === :quiet
            session.cli_session.quiet = session.quiet
        end
    end
    session.cli_session.verbosity = session.verbosity
    apply_kit_cli_session!(session.cli_session)
    return session
end

"""Resolved remote repository root for this session."""
function session_remote_root(session::KitSession)::String
    return resolve_remote_project_root(session.project; cli_override=session.remote)
end

"""Explain surface for this session (`:cli` or `:api`)."""
hint_surface(session::KitSession)::Symbol = session.cli_session.hint_surface

"""SSH host names used for [`size!`](@ref) (`parent` first when `include_parent_for_size`)."""
function session_size_hosts(session::KitSession)::Tuple{Vector{String},Vector{String}}
    child_hosts = copy(session.hosts)
    if session.include_parent_for_size
        return [PARENT_HOST_NAME; child_hosts], child_hosts
    end
    return child_hosts, child_hosts
end
