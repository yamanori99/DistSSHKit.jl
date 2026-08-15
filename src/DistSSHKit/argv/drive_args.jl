# Drive CLI argument parsing and help (module-owned; Main CLI re-exports).

function _parse_host_workers_spec(spec::AbstractString)
    return split_host_workers_spec(String(spec))
end

"""Parse `--flag:N` / `-f:N` into `N`; return `nothing` if `arg` is not that form."""
function _drive_flag_int_suffix(
    arg::String,
    prefixes::Union{Tuple{Vararg{String}}, AbstractVector{String}},
)::Union{Nothing,Int}
    for prefix in prefixes
        prefix_str = String(prefix)
        if !startswith(arg, prefix_str) || length(arg) <= length(prefix_str) || arg[length(prefix_str) + 1] != ':'
            continue
        end
        suffix = arg[(length(prefix_str) + 2):end]
        isempty(suffix) &&
            throw(ArgumentError("$(prefix_str) requires a worker count (e.g. $(prefix_str) 2 or $(prefix_str):2)"))
        return parse(Int, suffix)
    end
    return nothing
end

function _parse_drive_flag_count(flag::String, args::Vector, i::Int)::Int
    i >= length(args) &&
        throw(ArgumentError("$flag requires a worker count (e.g. $flag 2 or $(flag):2)"))
    value = String(args[i + 1])
    if endswith(value, ".jl")
        throw(ArgumentError(
            "$flag requires a worker count before the script (e.g. $flag 2 script.jl)",
        ))
    end
    try
        return parse(Int, value)
    catch
        throw(ArgumentError("$flag worker count must be an integer, got $(repr(value))"))
    end
end

"""Whether `host` / `host:N` denotes local worker processes (not SSH)."""
_drive_local_host_name(host_name::String)::Bool = is_local_host_name(host_name)

function _drive_set_local_workers!(
    local_workers::Int,
    count::Int,
    source::String,
)::Int
    local_workers > 0 &&
        throw(ArgumentError(
            "duplicate local worker spec ($source); use one of l:N, local:N, localhost:N, or --local N",
        ))
    count < 1 &&
        throw(ArgumentError("local worker count must be >= 1, got $count"))
    return count
end

function _drive_absorb_local_worker_spec(
    local_workers::Int,
    host_name::String,
    workers::Union{Int,Nothing},
    default_workers,
)::Tuple{Int,Bool}
    if !_drive_local_host_name(host_name)
        return local_workers, false
    end
    count = _drive_set_local_workers!(
        local_workers,
        something(workers, default_workers, 1),
        host_name * (workers === nothing ? "" : ":$workers"),
    )
    return count, true
end

function _drive_push_host_token!(
    hosts::Vector{Tuple{String,Union{Int,Nothing}}},
    local_workers::Int,
    token::AbstractString,
    default_workers,
)::Int
    host_name, host_workers = _parse_host_workers_spec(String(token))
    local_workers, absorbed = _drive_absorb_local_worker_spec(
        local_workers,
        host_name,
        host_workers,
        default_workers,
    )
    if !absorbed
        push!(hosts, (host_name, host_workers))
    end
    return local_workers
end

function parse_drive_args(args::Vector{String})
    cli_session, args = peel_kit_cli_flags(args)
    local_workers = 0
    default_workers = nothing
    julia_exe = nothing
    skip_hash_check = true  # default: no git parity; --require-git turns checks on
    enable_log = true
    log_dir = nothing
    output_dir = nothing
    explicit_package = nothing
    # nothing → no pre-run sync; :sync / :rsync → sync!
    sync_mode = nothing
    require_git = false
    skip_git_guard = false
    hosts = Tuple{String,Union{Int,Nothing}}[]
    script_path = nothing
    script_args = String[]

    i = 1
    while i <= length(args)
        arg = String(args[i])

        if arg == "--local" || arg == "-l"
            local_workers = _drive_set_local_workers!(
                local_workers,
                _parse_drive_flag_count(arg, args, i),
                arg,
            )
            i += 2
        elseif startswith(arg, "--local:") || startswith(arg, "-l:")
            count = _drive_flag_int_suffix(arg, ("--local", "-l"))
            count === nothing && throw(ArgumentError("local worker count missing in: $arg"))
            local_workers = _drive_set_local_workers!(local_workers, count, arg)
            i += 1
        elseif arg == "--workers" || arg == "-w"
            default_workers = _parse_drive_flag_count(arg, args, i)
            i += 2
        elseif startswith(arg, "--workers:") || startswith(arg, "-w:")
            default_workers = _drive_flag_int_suffix(arg, ("--workers", "-w"))
            i += 1
        elseif arg == "--julia" && i < length(args)
            julia_exe = args[i+1]
            i += 2
        elseif arg == "--sync"
            sync_mode = _kit_set_sync_mode!(sync_mode, :sync; source="drive")
            i += 1
        elseif arg == "--rsync"
            require_git && throw(ArgumentError(
                "drive: --require-git cannot be combined with --rsync",
            ))
            sync_mode = _kit_set_sync_mode!(sync_mode, :rsync; source="drive")
            i += 1
        elseif arg == "--require-git"
            sync_mode === :rsync && throw(ArgumentError(
                "drive: --require-git cannot be combined with --rsync",
            ))
            skip_git_guard && throw(ArgumentError(
                "drive: --require-git cannot be combined with --skip-git-guard",
            ))
            require_git && throw(ArgumentError("drive: --require-git specified more than once"))
            require_git = true
            skip_hash_check = false
            i += 1
        elseif arg == "--skip-git-guard"
            # Compat no-op for parity (already off). Independent of --sync / --rsync.
            require_git && throw(ArgumentError(
                "drive: --skip-git-guard cannot be combined with --require-git",
            ))
            skip_git_guard = true
            skip_hash_check = true
            i += 1
        elseif arg == "--no-log"
            enable_log = false
            i += 1
        elseif arg == "--log-dir" && i < length(args)
            log_dir = args[i+1]
            i += 2
        elseif arg == "--output-dir" && i < length(args)
            output_dir = args[i+1]
            i += 2
        elseif arg == "--package" && i < length(args)
            p = String(strip(args[i+1]))
            explicit_package = isempty(p) ? nothing : p
            i += 2
        elseif arg == "--collect" || arg == "--collect-sync"
            throw(ArgumentError(
                "$(arg) was removed; use --collect-missing ROOT HOST... or --collect-overwrite ROOT HOST...",
            ))
        elseif arg == "--collect-missing" ||
                arg == "--collect-overwrite"
            flag = arg
            merge = flag == "--collect-overwrite"
            sync_mode !== nothing &&
                throw(ArgumentError(
                    "$(flag) cannot be combined with --sync / --rsync",
                ))
            !isempty(hosts) &&
                throw(ArgumentError(
                    "host specs before $(flag) are not supported; use $(flag) ROOT HOST..."))
            tail = args[i+1:end]
            isempty(tail) && throw(ArgumentError("`$(flag)` requires ROOT HOST [HOST...]"))
            for a in tail
                if startswith(a, '-') && length(a) > 1
                    throw(ArgumentError(
                        "`$(flag)` arguments cannot include options like $(repr(a)); put flags before $(flag)"))
                end
            end
            tree_root = canonical_local_path(tail[1])
            tree_hosts = String[_parse_host_workers_spec(String(x))[1] for x in tail[2:end]]
            isempty(tree_hosts) && throw(ArgumentError("`$(flag)` requires at least one HOST after ROOT"))
            if julia_exe === nothing
                env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
                julia_exe = env_val == "auto" ? nothing : env_val
            elseif julia_exe == "auto"
                julia_exe = nothing
            end
            return (
                local_workers=local_workers,
                default_workers=default_workers,
                julia=julia_exe,
                skip_hash_check=skip_hash_check,
                enable_log=enable_log,
                log_dir=log_dir,
                output_dir=output_dir,
                explicit_package=explicit_package,
                hosts=Tuple{String,Union{Int,Nothing}}[],
                script_path=nothing,
                script_args=String[],
                collect_root=tree_root,
                collect_hosts=tree_hosts,
                collect_overwrite=merge,
                sync_mode=nothing,
                help=false,
                show_version=cli_session.show_version,
                cli_session=cli_session,
                hint_surface=:cli,
            )
        elseif arg == "--help" || arg == "-h"
            return (
                local_workers=0,
                default_workers=nothing,
                julia=nothing,
                skip_hash_check=true,
                enable_log=true,
                log_dir=nothing,
                output_dir=nothing,
                explicit_package=nothing,
                hosts=Tuple{String,Union{Int,Nothing}}[],
                script_path=nothing,
                script_args=String[],
                collect_root=nothing,
                collect_hosts=nothing,
                collect_overwrite=nothing,
                sync_mode=nothing,
                help=true,
                show_version=cli_session.show_version,
                cli_session=cli_session,
                hint_surface=:cli,
            )
        elseif endswith(arg, ".jl")
            script_path = arg
            script_args = args[i+1:end]
            break
        elseif startswith(arg, "-")
            throw(ArgumentError(
                "unknown or incomplete drive option: $arg (use host:N form, e.g. l:2 local:2 host1:4)",
            ))
        else
            local_workers = _drive_push_host_token!(
                hosts,
                local_workers,
                arg,
                default_workers,
            )
            i += 1
        end
    end

    if julia_exe === nothing
        env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
        julia_exe = env_val == "auto" ? nothing : env_val
    elseif julia_exe == "auto"
        julia_exe = nothing
    end

    # --rsync deploys without remote .git/; never run git parity.
    if sync_mode === :rsync
        require_git && throw(ArgumentError(
            "drive: --require-git cannot be combined with --rsync",
        ))
        skip_hash_check = true
    end

    for tok in kit_host_source_tokens(cli_session; keep_counts=true)
        local_workers = _drive_push_host_token!(
            hosts,
            local_workers,
            tok,
            default_workers,
        )
    end

    apply_kit_cli_session!(cli_session)

    return (
        local_workers=local_workers,
        default_workers=default_workers,
        julia=julia_exe,
        skip_hash_check=skip_hash_check,
        enable_log=enable_log,
        log_dir=log_dir,
        output_dir=output_dir,
        explicit_package=explicit_package,
        hosts=hosts,
        script_path=script_path,
        script_args=script_args,
        collect_root=nothing,
        collect_hosts=nothing,
        collect_overwrite=nothing,
        sync_mode=(sync_mode isa Symbol ? sync_mode : nothing),
        help=false,
        show_version=cli_session.show_version,
        cli_session=cli_session,
        hint_surface=:cli,
    )
end

function show_drive_requirements(; io::IO=stdout)
    print_help_chrome("DistSSHKit drive"; io=io)
    print_help_lines(io,
        "Driver + Distributed workers (pmap), then collect new files.",
        "Remotes: setup --rsync or --clone, then --instantiate.",
    )
    print_help_blank(io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit drive [workers...] DRIVER.jl",
        "  drive local:4 host1:8 jobs.jl",
        "  drive --collect-missing ROOT HOST...",
    )
    print_help_blank(io)
    print_help_section("Workers"; io=io)
    print_help_lines(io,
        "  host:N / local:N    N Distributed workers (not go slots)",
        "  l:N                 same as local:N",
        "  host                1 worker, or --workers default",
        "  $(KIT_HOSTS_FLAG_HELP)",
        "  --hosts-file PATH   one token per line (host:N kept)",
    )
    print_help_blank(io)
    print_help_section("Options"; io=io)
    print_help_lines(io,
        "  -w, --workers N     default when host has no :N",
        "  --sync / --rsync    optional pre-run (default: none)",
        "  --require-git       $(REQUIRE_GIT_MEANING)",
        "  --output-dir PATH   result root (DISTRIBUTED_OUTPUT_DIR)",
        "  --julia PATH        remote Julia",
        "  --no-log            skip drive_*.log",
        "  $(KIT_QUIET_FLAG_HELP)",
        "  $(KIT_PROGRESS_FLAG_HELP)",
        "  $(KIT_VERBOSE_FLAG_HELP)",
        "  -y, --yes           skip confirmations",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank(io)
    print_help_section("Collect"; io=io)
    print_help_lines(io,
        "  After main(): post-run-new (files newer than run start).",
        "  Later: --collect-missing / --collect-overwrite ROOT HOST...",
        "  Skip auto-collect: DISTRIBUTED_SKIP_COLLECT=1",
    )
    print_help_blank(io)
    print_help_lines(io,
        "Details: docs (manual/drive). See also: setup, size, go.",
    )
end

show_drive_usage(; io::IO=stdout) = show_drive_requirements(; io)
drive_help_text()::String = sprint(io -> show_drive_requirements(; io))
