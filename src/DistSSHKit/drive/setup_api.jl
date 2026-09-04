# setup! — Julian mirror of `julia -m DistSSHKit setup --<mode>`.

const _SETUP_BANG_MODES = (
    :delete,
    :rsync,
    :clone,
    :sync,
    :pull,
    :instantiate,
    :juliaup,
    :check,
    :runtest,
    :cleanup,
    :prune,
)

"""
    setup!(session::KitSession, mode::Symbol; kwargs...) -> SyncResult
    setup!(session::KitSession, modes::Symbol...) -> SyncResult

Prepare SSH hosts — same jobs as `julia -m DistSSHKit setup --…`.

| `mode` | CLI | Notes |
| --- | --- | --- |
| `:delete` | `--delete` | Destructive; confirm unless `session.yes` |
| `:rsync` | `--rsync` | Refuses nonempty remote; delete first to replace |
| `:clone` | `--clone` | Requires `repo=`; clone runs **on the remote** |
| `:sync` | `--sync` | Local push + remote pull (git remotes); confirm unless `session.yes` |
| `:pull` | `--pull` | Local pull then remote pull; confirm unless `session.yes` |
| `:instantiate` | `--instantiate` | `julia=` (default `"auto"`) |
| `:juliaup` | `--juliaup` | Align Julia via juliaup on SSH hosts and/or `parent` (`\$HOME/.juliaup` or Homebrew); confirm unless `session.yes`. Tip if kit parent patch lags channel latest |
| `:check` | `--check` | `ignore_julia_version=`, `check_code_sync=` |
| `:runtest` | `--runtest` | job `Pkg.test()` on remotes; `julia=` |
| `:cleanup` | `--cleanup` | Kill stale workers (no confirm) |
| `:prune` | `--prune` | `.distsshkit` go/drive/setup leaves; confirm unless `session.yes`. `older_days=`, `id=` |

Confirmations follow `session.yes` (CLI `-y`). Multiple modes run in order and
stop on the first failure:

```julia
session = KitSession(workers=["child:user@h1"], remote="~/proj", yes=true)
setup!(session, :delete, :rsync, :instantiate)
setup!(session, :check; ignore_julia_version=true)
```

[`sync!`](@ref) / [`instantiate!`](@ref) remain as thin aliases for the common
deploy steps. Prefer `setup!` when you want the full CLI vocabulary in one place.
"""
function setup!(
    session::KitSession,
    mode::Symbol;
    repo::Union{Nothing,AbstractString}=nothing,
    julia::AbstractString="auto",
    ignore_julia_version::Bool=false,
    check_code_sync::Bool=true,
    older_days::Union{Nothing,Integer}=nothing,
    id::Union{Nothing,AbstractString}=nothing,
)::SyncResult
    _setup_bang_preflight!(session, mode; repo=repo)
    apply_session_env!(session)
    log_dir = joinpath(session.project, ".distsshkit", "setup")
    step = setup_progress_step_name(mode)
    return with_kit_setup_progress(
        log_dir,
        step;
        path_anchor=session.project,
    ) do
        _setup_one!(
            session,
            mode;
            repo=repo,
            julia=julia,
            ignore_julia_version=ignore_julia_version,
            check_code_sync=check_code_sync,
            older_days=older_days,
            id=id,
        )
    end
end

function setup!(session::KitSession, mode::Symbol, more::Symbol...; kwargs...)
    modes = (mode, more...)
    if !isempty(kwargs) && length(modes) > 1
        throw(ArgumentError(
            "setup! with multiple modes does not take keyword arguments; " *
            "call setup!(session, mode; …) per step, or pass modes that need no kwargs",
        ))
    end
    local result = SyncResult(false, HostResult[]; ok=true)
    for m in modes
        result = setup!(session, m; kwargs...)
        result.ok || return result
    end
    return result
end

"""Non-empty clone URL, or throw."""
function _setup_clone_url(
    repo::Union{Nothing,AbstractString};
    surface::Symbol=:api,
)::String
    repo === nothing && throw(ArgumentError(
        explain_clone_repo_required(; surface=surface),
    ))
    url = strip(String(repo))
    isempty(url) && throw(ArgumentError("setup! :clone repo= must be a non-empty git URL"))
    return url
end

function _setup_bang_preflight!(
    session::KitSession,
    mode::Symbol;
    repo::Union{Nothing,AbstractString}=nothing,
)
    mode in _SETUP_BANG_MODES || throw(ArgumentError(
        "setup! mode must be one of $(_SETUP_BANG_MODES), got $(repr(mode))",
    ))
    if mode === :clone
        _setup_clone_url(repo; surface=hint_surface(session))
    end
    return nothing
end

function _setup_one!(
    session::KitSession,
    mode::Symbol;
    repo::Union{Nothing,AbstractString}=nothing,
    julia::AbstractString="auto",
    ignore_julia_version::Bool=false,
    check_code_sync::Bool=true,
    older_days::Union{Nothing,Integer}=nothing,
    id::Union{Nothing,AbstractString}=nothing,
)::SyncResult
    _setup_bang_preflight!(session, mode; repo=repo)
    hosts = _setup_bang_hosts!(session; allow_parent=mode === :juliaup)
    remote_path = session_remote_root(session)
    julia_path = isempty(strip(String(julia))) ? "auto" : String(julia)

    if mode === :delete
        preflight_setup_ssh(hosts) || return SyncResult(true, HostResult[]; ok=false)
        raw = delete_remotes(hosts, remote_path; confirm=!session.yes)
        return _sync_result_from_host_op(raw)
    elseif mode === :rsync
        return sync!(session; mode=:rsync)
    elseif mode === :clone
        url = normalize_git_clone_url(_setup_clone_url(repo; surface=hint_surface(session)))
        preflight_setup_ssh(hosts) || return SyncResult(true, HostResult[]; ok=false)
        raw = clone_to_remotes(hosts, remote_path, url; confirm=!session.yes)
        return _sync_result_from_host_op(raw)
    elseif mode === :sync
        return sync!(session; mode=:sync)
    elseif mode === :pull
        apply_session_env!(session)
        raw = git_sync_project_to_hosts!(
            hosts,
            session.project,
            remote_path;
            do_push=false,
            do_pull=true,
            do_local_pull=true,
            confirm=!session.yes,
        )
        if raw.cancelled
            return SyncResult(true, HostResult[]; ok=false)
        end
        return SyncResult(false, raw.host_results; ok=raw.ok)
    elseif mode === :instantiate
        return instantiate!(session; julia=julia_path)
    elseif mode === :juliaup
        ssh_hosts = setup_juliaup_ssh_hosts(hosts)
        if !isempty(ssh_hosts)
            preflight_setup_ssh(ssh_hosts) || return SyncResult(true, HostResult[]; ok=false)
        end
        raw = juliaup_align_remotes(hosts; confirm=!session.yes)
        return _sync_result_from_host_op(raw)
    elseif mode === :runtest
        preflight_setup_ssh(hosts) || return SyncResult(true, HostResult[]; ok=false)
        raw = runtest_remotes(
            hosts, julia_path, remote_path, session.project;
            path_anchor=session.project,
        )
        return _sync_result_from_host_op(raw)
    elseif mode === :check
        result = check_prerequisites(
            hosts,
            julia_path,
            remote_path,
            session.project;
            path_anchor=session.project,
            require_clean_git=false,
            check_code_sync=check_code_sync,
            ignore_julia_version=ignore_julia_version,
        )
        if result.ok
            print_ok("All prerequisites met.")
            kit_println()
        else
            print_err("Prerequisites not met. Fix issues above and retry.")
            kit_println()
        end
        return SyncResult(false, HostResult[]; ok=result.ok)
    elseif mode === :cleanup
        raw = cleanup_remote_workers(hosts)
        return _sync_result_from_host_op(raw)
    elseif mode === :prune
        preflight_setup_ssh(hosts) || return SyncResult(true, HostResult[]; ok=false)
        log_dir = joinpath(session.project, ".distsshkit", "setup")
        raw = prune_kit_leaves(
            hosts,
            remote_path,
            session.project;
            confirm=!session.yes,
            older_days=older_days,
            id=id,
            skip_setup=log_dir,
        )
        return _sync_result_from_host_op(raw)
    end
    # Unreachable when `_SETUP_BANG_MODES` stays in sync with branches above.
    throw(ArgumentError("setup! mode $(repr(mode)) is not implemented"))
end

function _setup_bang_hosts!(session::KitSession; allow_parent::Bool=false)
    apply_session_env!(session)
    hosts = copy(session.hosts)
    if allow_parent
        # `session.hosts` is SSH children only; parent lives on `tokens`.
        for t in session.tokens
            pt = try
                parse_placement_token(t)
            catch
                nothing
            end
            pt === nothing && continue
            if pt.role === :parent
                push!(hosts, PARENT_HOST_NAME)
                break
            end
        end
    end
    isempty(hosts) && throw(ArgumentError(
        explain_no_hosts(; surface=hint_surface(session), kind=:ssh),
    ))
    validate_setup_hosts(hosts; allow_parent=allow_parent)
    return hosts
end

function _sync_result_from_host_op(raw)::SyncResult
    hrs = hasproperty(raw, :hosts) ? collect(HostResult, raw.hosts) : HostResult[]
    return SyncResult(
        raw.cancelled,
        hrs;
        ok=!raw.cancelled && raw.failed == 0,
    )
end
