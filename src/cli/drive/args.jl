# Runner CLI argument parsing and help text.

function _parse_host_workers_spec(spec::AbstractString)
    return DistSSHKit.split_host_workers_spec(String(spec))
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
_drive_local_host_name(host_name::String)::Bool = DistSSHKit.is_local_host_name(host_name)

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

function parse_drive_args(args::Vector{String})
    cli_session, args = DistSSHKit.peel_kit_cli_flags(args)
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
            sync_mode = DistSSHKit._kit_set_sync_mode!(sync_mode, :sync; source="drive")
            i += 1
        elseif arg == "--rsync"
            require_git && throw(ArgumentError(
                "drive: --require-git cannot be combined with --rsync",
            ))
            sync_mode = DistSSHKit._kit_set_sync_mode!(sync_mode, :rsync; source="drive")
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
            tree_root = DistSSHKit.canonical_local_path(tail[1])
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
            host_name, host_workers = _parse_host_workers_spec(arg)
            local_workers, absorbed = _drive_absorb_local_worker_spec(
                local_workers,
                host_name,
                host_workers,
                default_workers,
            )
            if !absorbed
                push!(hosts, (host_name, host_workers))
            end
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

    hosts_file = cli_session.hosts_file
    if hosts_file !== nothing
        for line in DistSSHKit.read_hosts_file_lines(hosts_file)
            host_name, host_workers = _parse_host_workers_spec(line)
            local_workers, absorbed = _drive_absorb_local_worker_spec(
                local_workers,
                host_name,
                host_workers,
                default_workers,
            )
            if !absorbed
                push!(hosts, (host_name, host_workers))
            end
        end
    end

    # Same ENV as go / pipeline_config_from_env (always append; host:N OK).
    raw_hosts_env = strip(get(ENV, "DISTSSHKIT_HOSTS", ""))
    if !isempty(raw_hosts_env)
        for h in split(raw_hosts_env, ',')
            s = strip(h)
            isempty(s) && continue
            host_name, host_workers = _parse_host_workers_spec(s)
            local_workers, absorbed = _drive_absorb_local_worker_spec(
                local_workers,
                host_name,
                host_workers,
                default_workers,
            )
            if !absorbed
                push!(hosts, (host_name, host_workers))
            end
        end
    end

    DistSSHKit.apply_kit_cli_session!(cli_session)

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
    )
end

function show_drive_requirements()
    print_help_chrome("DistSSHKit drive")
    print_help_lines(
        "Add local and/or SSH worker processes, run a driver script with pmap,",
        "then rsync **new** result files from remotes back to local.",
    )
    print_help_blank()
    print_help_section("Prerequisites (run `setup --check` first on new clusters)")
    print_help_lines(
        "  1. SSH key auth to remote hosts (ssh-copy-id user@host)",
        "  2. Project tree on remotes (setup --rsync recommended, or --clone / --sync)",
        "  3. Instantiated deps on remotes (setup --instantiate)",
        "  4. Julia on remotes (auto-detected, or --julia / JULIA_DISTRIBUTED_EXE)",
        "  5. Same repo layout on workers, or set DISTRIBUTED_REMOTE_PROJECT_ROOT",
        "  6. Optional: --require-git if you want remote commit parity",
    )
    print_help_blank()
    print_help_section("Optional pre-run sync (default: none — run setup yourself)")
    print_help_lines(
        "  --sync              git push/pull before run (same as setup --sync)",
        "  --rsync             rsync working tree first (missing/empty remote only)",
    )
    print_help_blank()
    print_help_section("Optional git parity (default: off)")
    print_help_lines(
        "  --require-git       $(DistSSHKit.REQUIRE_GIT_MEANING)",
        "  --skip-git-guard    $(DistSSHKit.SKIP_GIT_GUARD_MEANING)",
    )
    print_help_blank()
    print_help_section("First-time on remotes (before drive)")
    print_help_lines(
        "  julia --project=. -m DistSSHKit setup --rsync host1 host2",
        "  julia --project=. -m DistSSHKit setup --instantiate host1 host2",
        "  julia --project=. -m DistSSHKit setup --check --ignore-julia-version host1 host2",
    )
    print_help_blank()
    print_help_section("Daily workflow")
    print_help_lines(
        "  # After setup --rsync (or --sync), just run:",
        "  julia --project=. -m DistSSHKit drive \\",
        "    local:4 host1:8 host2:8 scripts/jobs.jl --config cfg.json",
        "  # Optional one-shot sync: drive --sync ... or drive --rsync ...",
        "  # Optional git parity: drive --require-git --sync ...",
    )
    print_help_blank()
    print_help_section("Quick iteration")
    print_help_lines(
        "  julia --project=. -m DistSSHKit drive --rsync \\",
        "    local:4 host1:8 host2:8 scripts/jobs.jl",
        "  # Or: setup --rsync ... && drive ...",
        "",
        "  # Optional: kill stale workers left from a crashed run",
        "  julia --project=. -m DistSSHKit setup --cleanup host1 host2",
    )
    print_help_blank()
    print_help_section("Worker counts")
    print_help_lines(
        "  host:N        N workers (user@host:N OK; l:N / local:N / localhost:N for local)",
        "  host          1 worker, or --workers default if set",
        "  --local N     alias for local:N (also --local:N)",
        "  --hosts-file  append hosts from a file (# comments, host:N lines)",
    )
    print_help_blank()
    print_help_section("Results / collect")
    print_help_lines(
        "  --output-dir PATH  result root (sets DISTRIBUTED_OUTPUT_DIR); not go's batch root",
        "  Default driver root: <script_dir>/output via init_output_dir!",
        "  Override: --output-dir / ENV / script_args --output-dir",
        "",
    )
    println(DistSSHKit.COLLECT_MODE_HELP)
    print_help_lines(
        "  After main(): post-run-new from collect dirs (DISTRIBUTED_OUTPUT_DIR or",
        "                <script_dir>/../results; override via DISTRIBUTED_COLLECT_DIRS).",
        "  Skip auto-collect: export DISTRIBUTED_SKIP_COLLECT=1",
        "  Or later: drive --collect-missing data/sweep host1 host2",
    )
    print_help_blank()
    print_help_section("Quiet / confirm")
    print_help_lines(
        "  $(DistSSHKit.KIT_QUIET_FLAG_HELP)",
        "  $(DistSSHKit.KIT_PROGRESS_FLAG_HELP)",
        "  --no-log            Do not write drive_<timestamp>.log",
        "  -y, --yes           Auto-answer prompts (e.g. memory pressure Continue? [y/N])",
        "  export DISTSSHKIT_QUIET=1          Same as --quiet",
        "  export DISTSSHKIT_PROGRESS=1      Same as --progress",
        "  export DISTSSHKIT_YES=1            Same as -y",
    )
    print_help_blank()
    print_help_section("Driver script")
    print_help_lines(
        "  Top level: definitions only (no side effects at include time).",
        "  Optional init_output_dir!(script_args) → sets DISTRIBUTED_OUTPUT_DIR.",
        "  Optional prepare_workers!() for per-worker setup after sync.",
        "  Runner: include on master → sync to workers → main() on master.",
        "  Distributed.jl processes (not threads); use -t N for threading in-process.",
    )
    print_help_blank()
    print_help_section("Sizing workers")
    print_help_lines(
        "  julia --project=. -m DistSSHKit size --local host1 host2",
    )
    print_help_blank()
    print_help_section("More detail")
    print_help_lines(
        "  julia --project=. -m DistSSHKit drive --help",
        "  julia --project=. -m DistSSHKit setup --help",
    )
    print_help_blank()
end

function drive_help_text()::String
    """
Usage:
  julia --project=. -m DistSSHKit drive [options] [hosts...] script.jl [script_args...]

Collect-only (no script; flags and ROOT/HOSTS at end of argv):
  julia --project=. -m DistSSHKit drive --collect-missing ROOT HOST [HOST...]
  julia --project=. -m DistSSHKit drive --collect-overwrite ROOT HOST [HOST...]

Modes:
  (default)              Run script.jl after workers are added and the driver is synced
  --collect-missing      Rsync files under ROOT that exist on hosts but not locally
  --collect-overwrite    Rsync-merge entire tree under ROOT (overwrite local same names)

Argument order (run mode):
  1. Runner options (-w, --sync, --rsync, --require-git, -q, -y, …; --local N = local:N)
  2. Host specs (host or host:N; l:N / local:N / localhost:N for local workers)
  3. script.jl (first path ending in .jl)
  4. script_args... (passed to ARGS during main(); often parsed by init_output_dir!)

  Collect-only: put --collect-missing/--collect-overwrite last, then ROOT HOST...
  (no host specs before the collect flag; no script.jl)

Workflow (script run):
  1. Activate project — Pkg.activate from nearest Project.toml above script.jl
  2. Include driver on master; optional init_output_dir!(script_args) on master only
  3. Open drive log (unless --no-log) at <log_dir>/drive_<timestamp>.log
  4. Git checks — off by default; with --require-git: warn if local dirty; compare
     remote short hashes (exit 1 on mismatch / missing remote .git/)
  5. Cleanup — kill stale Julia worker processes (local + listed remotes)
  6. Memory — estimate per-worker RSS; warn if >$(round(Int, DistSSHKit.MEMORY_CAPACITY_FRACTION * 100))% of host RAM; prompt unless -y
  7. Workers — addprocs local:N (or l:N); SSH addprocs per host (host:N or --workers default)
  8. Init — ping workers; activate project; `using` package on every process
  9. Sync — re-include driver on every process (definitions for pmap)
 10. prepare_workers! — optional @everywhere hook if driver defines it
 11. Run — ENV["DISTRIBUTED_RUNNER"]="1"; call main() on master via invokelatest
 12. Collect — rsync files newer than run-start sentinel from collect dirs (unless skip)

Worker counts:
  Local:   l:N, local:N, or localhost:N (default 0 → master only)
  Remote:  host:N → N workers; host alone → --workers if set, else 1
  Alias:   --local N / --local:N (same as local:N)
  Duplicate host lines sum (host1:4 host1:2 → 6 workers on host1)
  --hosts-file PATH appends lines after CLI hosts (`#` comments; host:N allowed)

Git parity (--require-git only):
  Local:   uncommitted changes → warning (run may not match any git commit)
  Remotes: git commit hash at remote project root must match local project dir
           Remote root: DISTRIBUTED_REMOTE_PROJECT_ROOT if set, else local proj_dir
           On mismatch or missing remote .git/ → exit 1; fix with setup --clone / --sync,
           or omit --require-git after setup --rsync

--collect-missing vs --collect-overwrite:
  --collect-missing   collect-missing: recursive rsync of remote files absent locally
                      (good for sweep shards written only on workers)
  --collect-overwrite collect-overwrite: merge remote tree; same paths replaced from remote
                      (good when workers may update files you already have locally)

Post-run collect (automatic after script run) = post-run-new:
  Before main(), drive places a timestamp sentinel on each remote collect root.
  After main(), rsync only files newer than that sentinel (not the whole tree every time).
  Collect roots (first match wins):
    ENV DISTRIBUTED_COLLECT_DIRS — colon-separated abs or repo-relative paths
    else ENV DISTRIBUTED_OUTPUT_DIR
    else <script_dir>/../results
  Scripts writing to multiple trees should set DISTRIBUTED_COLLECT_DIRS
  (e.g. data/sweep:figures). Logs can stay in DISTRIBUTED_OUTPUT_DIR only.
  Skip all post-run collect: DISTRIBUTED_SKIP_COLLECT=1
  Remote path mapping for collect/addprocs uses DISTRIBUTED_REMOTE_PROJECT_ROOT
  when set (absolute path on the SSH host; `~/...` is expanded locally — usually wrong).
  go uses slot-overwrite (full slot dir rsync) instead of post-run-new.

Driver script expectations:
  - Top level: function/const definitions only — no IO, no addprocs, no main() at include
  - init_output_dir!(script_args) optional — sets DISTRIBUTED_OUTPUT_DIR for logs + default collect
  - prepare_workers!() optional — worker-local setup after driver sync (@everywhere)
  - main() required for run mode — invoked on master only; use pmap/remotecall inside
  - Avoid module blocks and mutating const (re-include on workers can fail)
  - Prefer pmap after sync; DistSSHKit.worker_pmap for Julia 1.12+ world-age edge cases
  - Driver is included twice (master, then @everywhere sync) — keep top level pure

Output / logging:
  --output-dir PATH     Result root → DISTRIBUTED_OUTPUT_DIR (logs + default collect).
                        Not the same as go --output-dir (go: batch root for slots).
  else driver init_output_dir! / export / script_args --output-dir
  Console mirrored to <log_dir>/drive_YYYYMMDDTHHMMSS.log unless --no-log.
  Log dir: --log-dir → DISTRIBUTED_OUTPUT_DIR → <script_dir>/results

Confirmation prompts (skip with -y / DISTSSHKIT_YES):
  Memory pressure after step 6 → Continue anyway? [y/N]

Options:
  -l, --local N         Alias for local:N (default: 0)
  -w, --workers N       Default count for hosts without :N suffix (incl. local)
  --julia PATH          Julia on remotes (default: \$JULIA_DISTRIBUTED_EXE or auto-detect)
  --sync                Pre-run git push/pull (optional; default is no pre-run sync)
  --rsync               Pre-run rsync deploy (missing/empty remote only)
  --require-git         $(DistSSHKit.REQUIRE_GIT_MEANING)
  --skip-git-guard      $(DistSSHKit.SKIP_GIT_GUARD_MEANING)
  --no-log              Do not write drive_<timestamp>.log
  --output-dir PATH     Result + default log/collect root (not go batch root)
  --log-dir PATH        Log directory override (default: DISTRIBUTED_OUTPUT_DIR or <script_dir>/results)
  --package NAME        `using NAME` on workers (overrides Project.toml package name)
  -q, --quiet           Suppress terminal detail and job echo (kit log / logged job stdout still written)
  $(DistSSHKit.KIT_PROGRESS_FLAG_HELP)
  -y, --yes             Non-interactive (memory confirmation, etc.)
  --hosts-file PATH     Append hosts from a line-oriented file (`#` comments allowed)
  --version, -v         Print DistSSHKit version and exit
  -h, --help            Show this help

Arguments:
  hosts...        host or host:N (e.g. user@host:10, l:4, local:4, localhost:4)
  script.jl       Driver script path (required for run mode)
  script_args...  Appended to ARGS for main(); often consumed by init_output_dir!

Environment:
  JULIA_DISTRIBUTED_EXE             Default Julia path for remote hosts
  DISTRIBUTED_PROJECT_ROOT          Local project root override (absolute path)
  DISTRIBUTED_OUTPUT_DIR            Result root; set by --output-dir or init_output_dir!
  DISTRIBUTED_COLLECT_DIRS          Colon-separated dirs to collect after runs (abs or repo-relative)
  DISTRIBUTED_REMOTE_PROJECT_ROOT   Repo root on SSH hosts (git hash check, addprocs, collect).
                                    setup SSH: `~` OK per remote shell.
                                    drive collect / addprocs: prefer absolute remote path.
  DISTRIBUTED_SSH_OPTS              SSH options (space-separated; e.g. -o ProxyJump=bastion)
  DISTRIBUTED_SKIP_COLLECT          1 → skip post-run rsync from remotes
  DISTRIBUTED_INIT_DELAY_SEC        Seconds to wait after addprocs (default: 5)
  DISTRIBUTED_PING_RETRIES          Worker ping attempts during init (default: 6)
  $(DistSSHKit.KIT_QUIET_ENV_HELP)
  $(DistSSHKit.KIT_PROGRESS_ENV_HELP)
  DISTSSHKIT_YES                    Same as --yes
  DISTSSHKIT_HOSTS                  Comma-separated hosts (host or host:N); appended like --hosts-file
  DISTSSHKIT_HOSTS_FILE             Default --hosts-file path

Prerequisites:
  - SSH key authentication to remote hosts
  - Project tree + instantiate on remotes (setup --rsync or --clone, then --instantiate)
  - Host project loadable via Project.toml near the driver script
  - Same project layout on workers, or DISTRIBUTED_REMOTE_PROJECT_ROOT set consistently
  - Driver safe to re-include on all worker processes
  - Optional --require-git when you want remote commit parity

Examples:
  # Quick start (no script = workflow summary)
  julia --project=. -m DistSSHKit drive

  # Recommended first-time then run
  julia --project=. -m DistSSHKit setup --rsync host1 host2
  julia --project=. -m DistSSHKit setup --instantiate host1 host2
  julia --project=. -m DistSSHKit drive local:4 host1:8 host2:8 scripts/jobs.jl

  # Suggest worker counts from RAM/CPU
  julia --project=. -m DistSSHKit size --local host1 host2

  # Default worker count + hosts file
  julia --project=. -m DistSSHKit drive --workers 10 --hosts-file hosts.txt host1 script.jl

  # Local workers only (short forms)
  julia --project=. -m DistSSHKit drive l:9 script.jl

  # Remote only (master on laptop, workers on SSH hosts)
  julia --project=. -m DistSSHKit drive user@host1:10 script.jl

  # One-shot rsync then run
  julia --project=. -m DistSSHKit drive --rsync host1:4 script.jl

  # Optional pre-run git sync; add --require-git for commit parity
  julia --project=. -m DistSSHKit drive --sync local:2 host1:4 script.jl
  julia --project=. -m DistSSHKit drive --require-git --sync host1:4 script.jl

  # Custom package name on workers
  julia --project=. -m DistSSHKit drive --package MyApp host1:4 script.jl

  # Collect-only: missing remote files
  julia --project=. -m DistSSHKit drive --collect-missing data/sweep host1 host2

  # Collect-only: merge whole tree from remotes
  julia --project=. -m DistSSHKit drive --collect-overwrite results host1

  # SSH bastion
  export DISTRIBUTED_SSH_OPTS="-o ProxyJump=bastion.example"

  # Custom remote repo root (absolute on SSH hosts)
  export DISTRIBUTED_REMOTE_PROJECT_ROOT=/data/shared/MyApp.jl

Removed:
  --collect / --collect-sync  use --collect-missing / --collect-overwrite instead

Note:
  Uses Distributed.jl (multi-process). Each worker is a separate Julia process.
  For multi-threading in one process, run your script directly with -t N.

See also: `julia -m DistSSHKit setup --help`, `julia -m DistSSHKit size --help`, README.md
"""
end

function show_drive_usage()
    DistSSHKit.print_help_document("DistSSHKit drive", drive_help_text())
end
