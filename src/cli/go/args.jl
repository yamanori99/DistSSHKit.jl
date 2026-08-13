# Argument parsing for `go.jl` (as-is complete jobs).

function show_go_usage()
    print_help_chrome("DistSSHKit go")
    print_help_lines(
        "Standalone script. One full run per slot; slots start together.",
        "Remotes: setup --rsync or --clone, then --instantiate.",
    )
    print_help_blank()
    print_help_section("Usage")
    print_help_lines(
        "  julia --project=. -m DistSSHKit go [slots...] SCRIPT.jl",
        "  go local:2 SCRIPT.jl",
        "  go local:1 host1:2 host2:2 SCRIPT.jl",
    )
    print_help_blank()
    print_help_section("Slots")
    print_help_lines(
        "  local:N / host:N    N full-script runs (not drive workers)",
        "  local:0             skip local when remotes are listed",
        "  --hosts CSV         same tokens, comma-separated",
        "  --hosts-file PATH   one token per line (host:N kept)",
    )
    print_help_blank()
    print_help_section("Options")
    print_help_lines(
        "  --sync / --rsync    optional pre-run (default: none)",
        "  --julia PATH        remote Julia (ENV or auto)",
        "  --output-dir PATH   batch root; slots are PATH/<slot>/",
        "  $(DistSSHKit.KIT_QUIET_FLAG_HELP)",
        "  $(DistSSHKit.KIT_PROGRESS_FLAG_HELP)",
        "  $(DistSSHKit.KIT_VERBOSE_FLAG_HELP)",
        "  -y, --yes           skip confirmations",
        "  --version, -v       print version and exit",
        "  -h, --help          this help",
    )
    print_help_blank()
    print_help_section("Output")
    print_help_lines(
        "  .distsshkit/go/<stem>_<UTC>/<slot>/",
        "  DISTRIBUTED_OUTPUT_DIR → that slot dir",
        "  --output-dir is the batch root (not drive's result root)",
    )
    print_help_blank()
    print_help_section("Environment")
    print_help_lines(
        "  DISTSSHKIT_HOSTS[, FILE]    hosts (host:N OK)",
        "  JULIA_DISTRIBUTED_EXE       default remote Julia",
        "  DISTSSHKIT_QUIET / PROGRESS / VERBOSE / YES",
    )
    print_help_blank()
    print_help_lines(
        "Details: docs (manual/go). See also: setup, drive.",
    )
end

function _go_set_sync!(current, next)
    return DistSSHKit._kit_set_sync_mode!(current, next; source="go")
end

"""Parse `go` CLI arguments (same shape as other kit CLI parsers)."""
function parse_go_args(args::AbstractVector{<:AbstractString})
    cli_session, rest = DistSSHKit.peel_kit_cli_flags(args)
    hosts = String[]
    host_tokens = String[]
    script_path = nothing
    script_args = String[]
    output_dir = nothing
    julia_exe = nothing
    # nothing → go! default (false); :sync / :rsync / false (= skip)
    sync = nothing
    c = DistSSHKit.CliCursor(collect(String, rest))
    while !DistSSHKit.cli_at_end(c)
        arg = DistSSHKit.cli_current(c)::String
        if arg == "--hosts"
            for h in split(DistSSHKit.cli_take_value!(c, arg), ',')
                s = strip(h)
                !isempty(s) && push!(hosts, s)
            end
        elseif arg == "--output-dir"
            output_dir = DistSSHKit.cli_take_value!(c, arg)
        elseif arg == "--julia"
            julia_exe = DistSSHKit.cli_take_value!(c, arg)
        elseif arg == "--sync"
            DistSSHKit.cli_consume!(c)
            sync = _go_set_sync!(sync, :sync)
        elseif arg == "--rsync"
            DistSSHKit.cli_consume!(c)
            sync = _go_set_sync!(sync, :rsync)
        elseif arg == "--skip-sync" || arg == "--skip-git-guard"
            DistSSHKit.cli_consume!(c)
            sync = _go_set_sync!(sync, false)
        elseif arg == "--help" || arg == "-h"
            DistSSHKit.cli_consume!(c)
            return (
                help=true,
                show_version=cli_session.show_version,
                cli_session=cli_session,
                script_path=nothing,
                script_args=String[],
                hosts=String[],
                sync=nothing,
                output_dir=nothing,
                julia=nothing,
            )
        elseif endswith(arg, ".jl")
            script_path = arg
            DistSSHKit.cli_consume!(c)
            while !DistSSHKit.cli_at_end(c)
                push!(script_args, DistSSHKit.cli_current(c)::String)
                DistSSHKit.cli_consume!(c)
            end
            break
        elseif !startswith(arg, "-")
            push!(host_tokens, arg)
            DistSSHKit.cli_consume!(c)
        else
            throw(ArgumentError("unknown go option: $arg"))
        end
    end
    append!(hosts, host_tokens)
    if julia_exe === nothing
        env_val = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")
        julia_exe = env_val == "auto" ? nothing : env_val
    elseif julia_exe == "auto"
        julia_exe = nothing
    end
    DistSSHKit.apply_kit_cli_session!(cli_session)
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
