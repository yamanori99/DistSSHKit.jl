# Argument parsing for `go` (as-is complete jobs).

"""Print `go --help` (same chrome as `julia -m DistSSHKit go -h`)."""
function show_go_usage(; io::IO=stdout)
    print_help_chrome("DistSSHKit go"; io=io)
    print_help_lines(io,
        "Standalone script. One full run per slot; slots start together.",
        "Remotes: setup --rsync or --clone, then --instantiate.",
    )
    print_help_blank(io)
    print_help_section("Usage"; io=io)
    print_help_lines(io,
        "  julia --project=. -m DistSSHKit go [slots...] SCRIPT.jl",
        "  go parenthost:2 SCRIPT.jl",
        "  go parenthost:1 host1:2 host2:2 SCRIPT.jl",
    )
    print_help_blank(io)
    print_help_section("Slots"; io=io)
    print_help_lines(io,
        "  parenthost:N / host:N  N full-script runs (not drive workers)",
        "  parenthost:0        skip parent when remotes are listed",
        "  $(KIT_HOSTS_FLAG_HELP)",
        "  --hosts-file PATH   one token per line (host:N kept)",
    )
    print_help_blank(io)
    print_help_section("Options"; io=io)
    print_help_lines(io,
        "  --sync / --rsync    optional pre-run (default: none)",
        "  --julia PATH        remote Julia (ENV or auto)",
        "  --output-dir PATH   batch root; slots are PATH/<slot>/",
        "  $(KIT_TIME_HELP)",
        "  $(KIT_QUIET_FLAG_HELP)",
        "  $(KIT_PROGRESS_FLAG_HELP)",
        "  $(KIT_VERBOSE_FLAG_HELP)",
        "  -y, --yes           skip confirmations",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank(io)
    print_help_section("Output"; io=io)
    print_help_lines(io,
        "  {script}/.distsshkit/go/<stem>_<UTC>/<slot>/",
        "  DISTRIBUTED_OUTPUT_DIR → that slot dir",
        "  --output-dir is the batch root (not drive's result root)",
    )
    print_help_blank(io)
    print_help_section("Environment"; io=io)
    print_help_lines(io,
        "  $(KIT_HOSTS_ENV_HELP)",
        "  JULIA_DISTRIBUTED_EXE       default remote Julia",
        "  DISTSSHKIT_QUIET / PROGRESS / VERBOSE / YES",
    )
    print_help_blank(io)
    print_help_lines(io,
        "Details: docs (manual/go). See also: setup, drive.",
    )
end

function _go_set_sync!(
    current::Union{Nothing,Symbol,Bool},
    next::Union{Symbol,Bool},
)
    return _kit_set_sync_mode!(current, next; source="go")
end

"""Parse `go` CLI arguments (same shape as other kit CLI parsers)."""
function parse_go_args(args::AbstractVector{<:AbstractString})
    cli_session, rest = peel_kit_cli_flags(args)
    hosts = String[]
    host_tokens = String[]
    script_path = nothing
    script_args = String[]
    output_dir = nothing
    julia_exe = nothing
    # nothing → go! default (false); :sync / :rsync / false (= skip)
    sync::Union{Nothing,Symbol,Bool} = nothing
    c = CliCursor(collect(String, rest))
    while !cli_at_end(c)
        arg = cli_current(c)::String
        if arg == "--output-dir"
            output_dir = cli_take_value!(c, arg)
        elseif arg == "--julia"
            julia_exe = cli_take_value!(c, arg)
        elseif arg == "--sync"
            cli_consume!(c)
            sync = _go_set_sync!(sync, :sync)
        elseif arg == "--rsync"
            cli_consume!(c)
            sync = _go_set_sync!(sync, :rsync)
        elseif arg == "--skip-sync" || arg == "--skip-git-guard"
            cli_consume!(c)
            sync = _go_set_sync!(sync, false)
        elseif arg == "--help" || arg == "-h"
            cli_consume!(c)
            append!(hosts, host_tokens)
            append_kit_host_sources!(hosts, cli_session; keep_counts=true)
            if julia_exe === nothing
                env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
                julia_exe = env_val == "auto" ? nothing : env_val
            elseif julia_exe == "auto"
                julia_exe = nothing
            end
            return (
                help=true,
                show_version=cli_session.show_version,
                cli_session=cli_session,
                script_path=script_path,
                script_args=script_args,
                hosts=hosts,
                sync=sync,
                output_dir=output_dir,
                julia=julia_exe,
            )
        elseif endswith(arg, ".jl")
            script_path = arg
            cli_consume!(c)
            while !cli_at_end(c)
                push!(script_args, cli_current(c)::String)
                cli_consume!(c)
            end
            break
        elseif !startswith(arg, "-")
            push!(host_tokens, arg)
            cli_consume!(c)
        else
            throw(ArgumentError("unknown go option: $arg"))
        end
    end
    append!(hosts, host_tokens)
    append_kit_host_sources!(hosts, cli_session; keep_counts=true)
    if julia_exe === nothing
        env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
        julia_exe = env_val == "auto" ? nothing : env_val
    elseif julia_exe == "auto"
        julia_exe = nothing
    end
    apply_kit_cli_session!(cli_session)
    return (
        help=false,
        show_version=cli_session.show_version,
        cli_session=cli_session,
        script_path=script_path,
        script_args=script_args,
        hosts=hosts,
        sync=sync,
        output_dir=output_dir,
        julia=julia_exe,
    )
end
