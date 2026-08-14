#!/usr/bin/env julia
"""
`julia -m DistSSHKit setup` — deploy and verify the project on SSH hosts.

Recommended workflow:
  1. --rsync → 2. --instantiate → 3. --check → `go` / `drive`
  Optional git: --clone → --instantiate → --check → --sync / --pull
  Replace a remote tree: --delete, then --rsync or --clone

  julia --project=. -m DistSSHKit setup --rsync hosts...
  julia --project=. -m DistSSHKit setup --sync hosts...   # git updates

See `--help`.
"""

# Guard on a setup-only import — not names `go`/`drive` may already have
# bound from DistSSHKit (e.g. `cli_project_root`) before `setup.jl` is included.
if !isdefined(@__MODULE__, :DistSSHKit)
    if get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", "") == "1"
        import DistSSHKit
    else
        try
            import DistSSHKit
        catch
            include(joinpath(@__DIR__, "..", "DistSSHKit.jl"))
        end
    end
end

if !isdefined(@__MODULE__, :resolve_remote_project_root)
    include(joinpath(@__DIR__, "setup", "_using.jl"))
end

if !isdefined(@__MODULE__, :setup_main)
    function setup_main()::Cint
        opts = parse_setup_args(ARGS)

        if opts.show_version
            DistSSHKit.println_kit_version()
            return 0
        end

        if opts.show_help
            show_usage()
            return 0
        end

        if opts.mode === nothing || opts.mode == :requirements
            show_requirements()
            return 0
        end

        try
            validate_setup_hosts(opts.hosts)
        catch e
            e isa ArgumentError || rethrow()
            # Fatal: always on terminal.
            print_err("Error: "; bold=true)
            println_fatal(e.msg)
            println_fatal()
            show_usage()
            return 1
        end

        project = String(DistSSHKit.cli_project_root(@__DIR__))
        path_anchor = DistSSHKit.canonical_local_path(project)
        remote_path = resolve_remote_project_root(
            project;
            cli_override=opts.remote_path_override,
        )

        init_log_file(
            joinpath(project, ".distsshkit", "setup");
            prefix="setup",
            path_anchor=path_anchor,
        )
        try
            mode_name = Dict(
                :clone => "Clone",
                :delete => "Delete",
                :check => "Check Prerequisites",
                :pull => "Pull",
                :sync => "Sync",
                :rsync_push => "rsync (no git)",
                :instantiate => "Instantiate",
                :cleanup => "Cleanup Workers",
            )[opts.mode]
            print_header("DistSSHKit setup · $mode_name")
            kit_println()
            writeln_field("Remote path", remote_path)
            kit_println()

            # Mutating / multi-host SSH ops: fail fast before confirmations.
            if opts.mode in (:delete, :clone, :rsync_push, :instantiate)
                if !preflight_setup_ssh(opts.hosts)
                    print_err("SSH preflight failed. Fix connectivity, then retry.")
                    kit_println()
                    return 1
                end
            end

            if opts.mode == :delete
                return finish_host_op!("Delete", delete_remotes(opts.hosts, remote_path)) ? 0 : 1
            end

            if opts.mode == :clone
                clone_url = resolve_clone_url(opts.repo_url, project)
                result = clone_to_remotes(opts.hosts, remote_path, clone_url)
                ok = finish_host_op!("Clone", result)
                if ok && !result.cancelled && result.failed == 0 &&
                   (opts.remote_path_override !== nothing ||
                    !isempty(strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))))
                    kit_println("  Tip: export DISTRIBUTED_REMOTE_PROJECT_ROOT=$remote_path")
                    kit_println("       so drive.jl uses the same remote root for workers / collect.")
                    kit_println()
                end
                return ok ? 0 : 1
            end

            if opts.mode == :rsync_push
                return finish_host_op!(
                    "rsync",
                    rsync_push_to_remotes(opts.hosts, remote_path, project; path_anchor=path_anchor),
                ) ? 0 : 1
            end

            if opts.mode == :instantiate
                return finish_host_op!(
                    "Instantiate",
                    instantiate_remotes(
                        opts.hosts, opts.julia_path, remote_path, project;
                        path_anchor=path_anchor,
                    ),
                ) ? 0 : 1
            end

            if opts.mode == :cleanup
                return finish_host_op!("Cleanup", cleanup_remote_workers(opts.hosts)) ? 0 : 1
            end

            # --pull/--sync: allow commit mismatch (fixed by the op). --check: require sync.
            # --sync also requires a clean local tree.
            require_clean = (opts.mode == :sync)
            check_code_sync = (opts.mode == :check)
            result = check_prerequisites(
                opts.hosts, opts.julia_path, remote_path, project;
                path_anchor=path_anchor,
                require_clean_git=require_clean,
                check_code_sync=check_code_sync,
                ignore_julia_version=opts.ignore_julia_version,
            )

            if !result.ok
                print_err("Prerequisites not met. Fix issues above and retry.")
                kit_println()
                return 1
            end

            if opts.mode == :check
                print_ok("All prerequisites met.")
                kit_println()
                return 0
            end

            if !result.needs_sync
                print_ok("Already up to date.")
                kit_println()
                return 0
            end

            print_ok("Ready to proceed.")
            kit_println()
            kit_println()

            # --pull: pull on localhost first, then on remotes
            # --sync: push from localhost, then pull on remotes
            do_push = (opts.mode == :sync)
            do_local_pull = (opts.mode == :pull)
            raw = git_sync_project_to_hosts!(
                opts.hosts,
                project,
                remote_path;
                do_push=do_push,
                do_pull=true,
                do_local_pull=do_local_pull,
            )
            if !raw.ok
                print_err("$mode_name failed.")
                kit_println()
                return 1
            end

            print_ok("$mode_name complete.")
            kit_println()
            return 0
        finally
            close_log_file()
        end
    end
end # setup_main guard

if get(ENV, "DIST_SSH_KIT_CLI_INCLUDE", "") != "1" &&
   !isempty(PROGRAM_FILE) &&
   abspath(PROGRAM_FILE) == abspath(@__FILE__)
    exit(setup_main())
end
