# Argument parsing for `go.jl` (as-is complete jobs).

function show_go_usage()
    print_help_chrome("DistSSHKit go")
    print_help_lines(
        "Run an as-is complete job (no Kit APIs in the script).",
        "Setup on remotes is assumed done (`setup --rsync` or `--clone`, then `--instantiate`).",
    )
    print_help_blank()
    print_help_section("Usage")
    print_help_lines(
        "  julia --project=. -m DistSSHKit go SCRIPT.jl [script_args...]",
        "  julia --project=. -m DistSSHKit go local:2 user@h1 user@h2:2 SCRIPT.jl",
        "  julia --project=. -m DistSSHKit SCRIPT.jl",
    )
    print_help_blank()
    print_help_section("Optional pre-run sync (default: none — run setup yourself)")
    print_help_lines(
        "  --sync              git push/pull — same as `setup --sync`",
        "  --rsync             rsync working tree first (missing/empty remote only;",
        "                      or `setup --delete` first)",
        "  --skip-sync         compat: no pre-run sync (already the default)",
        "  --skip-git-guard    $(DistSSHKit.GO_SKIP_GIT_GUARD_MEANING)",
        "  --julia PATH        Julia on remotes (default: \$JULIA_DISTRIBUTED_EXE or auto-detect)",
        "  --output-dir PATH   batch root (default: <project>/.distsshkit/go/<stem>_<UTC>)",
        "  --hosts CSV         Comma-separated slot specs (same form as CLI tokens)",
    )
    print_help_blank()
    print_help_section("Shared kit flags (also on drive / setup)")
    print_help_lines(
        "  $(DistSSHKit.KIT_QUIET_FLAG_HELP)",
        "  $(DistSSHKit.KIT_PROGRESS_FLAG_HELP)",
        "  -y, --yes           Non-interactive confirmations",
        "  --hosts-file PATH   Append hosts from a line-oriented file (host:N kept for slots)",
        "  --version, -v       Print DistSSHKit version and exit",
    )
    print_help_blank()
    println("Environment (hosts): DISTSSHKIT_HOSTS (comma-separated, host:N OK), DISTSSHKIT_HOSTS_FILE")
    println("Environment (Julia): JULIA_DISTRIBUTED_EXE (default remote Julia path)")
    print_help_blank()
    print_help_section("Typical after setup (`--rsync` or `--clone`, then `--instantiate`)")
    print_help_lines(
        "  julia --project=. -m DistSSHKit go \\",
        "    local:1 host1:2 host2:2 SCRIPT.jl",
        "  # Git updates later: setup --sync …, or go --sync …",
    )
    print_help_blank()
    print_help_lines(
        "Each slot runs the full script once. Default batch root:",
        "",
        "  <project>/.distsshkit/go/<stem>_<UTC>/<slot>/",
        "",
        "Override with --output-dir PATH (becomes the batch root; slots are PATH/<slot>/).",
        "Unlike drive --output-dir (result root / DISTRIBUTED_OUTPUT_DIR), go's flag is the",
        "batch directory that contains per-slot dirs.",
        "Kit sets DISTRIBUTED_OUTPUT_DIR to that slot directory (scripts may use it;",
        "standalone scripts can keep writing under their own output/).",
        "`local:N` / `host:N` = N full-job runs (not Distributed workers; use drive for those).",
        "`local:0` skips local slots when remotes are listed.",
        "",
        "See also: setup --help, drive --help",
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
