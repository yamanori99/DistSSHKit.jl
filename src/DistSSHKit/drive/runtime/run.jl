# Core drive execution after argv parse (shared by CLI `drive_main` and API `drive!`).

"""
    run_drive_parsed!(parsed; original_args=String[]) -> Cint

Run a driver from a `parse_drive_args`-shaped NamedTuple. Mutates `ARGS` to
`script_args` while the driver runs; callers should restore `ARGS` in `finally`.
"""
function run_drive_parsed!(
    parsed;
    original_args::Vector{String}=String[],
)::Cint
    if parsed.help
        show_drive_usage()
        return 0
    end

    if parsed.show_version
        DistSSHKit.println_kit_version()
        return 0
    end

    if parsed.collect_root !== nothing && parsed.collect_hosts !== nothing
        ok = drive_collect_tree(
            parsed.collect_root::String,
            parsed.collect_hosts::Vector{String};
            merge=something(parsed.collect_overwrite, false),
        )
        return ok ? 0 : 1
    end

    if parsed.script_path === nothing
        show_drive_requirements()
        return 0
    end

    hosts = parsed.hosts
    script_path = DistSSHKit.canonical_local_path(parsed.script_path::String)
    script_args = parsed.script_args
    local_workers = parsed.local_workers
    default_workers = parsed.default_workers
    julia_exe = parsed.julia
    skip_hash_check = parsed.skip_hash_check
    enable_log = parsed.enable_log
    log_dir = parsed.log_dir
    output_dir = parsed.output_dir
    explicit_package = parsed.explicit_package

    host_names = [h[1] for h in hosts]

    if !isfile(script_path)
        surface = hasproperty(parsed, :hint_surface) ? parsed.hint_surface::Symbol : :cli
        error(drive_script_not_found_message(script_path, _PATH_ANCHOR; surface=surface))
    end

    script_dir = dirname(script_path)
    proj_dir = resolve_pkg_project_dir(script_dir)

    activate_drive_project!(proj_dir)

    if output_dir !== nothing
        ENV["DISTRIBUTED_OUTPUT_DIR"] = DistSSHKit.canonical_local_path(String(output_dir))
    end

    include(script_path)
    if isdefined(Main, :init_output_dir!)
        @invokelatest Main.init_output_dir!(script_args)
    end

    if enable_log
        resolved_log_dir = log_dir
        if resolved_log_dir === nothing
            resolved_log_dir = get(ENV, "DISTRIBUTED_OUTPUT_DIR", nothing)
        end
        if resolved_log_dir === nothing
            resolved_log_dir = joinpath(script_dir, "results")
        end
        init_log_file(String(resolved_log_dir); prefix="drive", path_anchor=_PATH_ANCHOR)
        atexit(close_log_file)
    end

    writeln_field("Subcommand args", subcommand_args_record("drive", original_args))
    for (label, value) in julia_env_record()
        writeln_field(label, value)
    end
    writeln_both("")

    print_header("DistSSHKit drive")
    writeln_both("")
    writeln_field("Script", display_path(script_path, _PATH_ANCHOR))
    writeln_field("Args", isempty(script_args) ? "—" : join(script_args, " "))
    writeln_field("Project", cli_project_disp(proj_dir, _PATH_ANCHOR))
    writeln_field("DistSSHKit", dist_ssh_kit_version())
    app_git = get_local_git_hash(proj_dir; short=8)
    writeln_field("App git", app_git === nothing ? "unavailable" : app_git)
    writeln_both("")

    sync_mode = get(parsed, :sync_mode, nothing)
    do_sync = sync_mode isa Symbol && !isempty(host_names)
    # sync? + git + cleanup + workers + init + run + collect
    progress_steps = (do_sync ? 1 : 0) + 6
    progress_ok = false
    kit_progress_begin!("drive"; steps=progress_steps)
    try
        if do_sync
            kit_progress_step!("sync")
            writeln_both("Syncing to remotes ($(sync_mode))...")
            sync_session = DistSSHKit.KitSession(
                project=proj_dir,
                workers=host_names,
                quiet=parsed.cli_session.quiet,
                verbosity=parsed.cli_session.verbosity,
                yes=parsed.cli_session.yes || DistSSHKit.kit_noninteractive(),
            )
            sync_result = DistSSHKit.sync!(sync_session; mode=sync_mode)
            if !sync_result.ok
                print_err("ERROR: "; bold=true)
                println_fatal("pre-run sync failed")
                for hr in sync_result.hosts
                    !hr.ok && println_fatal("  $(hr.host): $(hr.message)")
                end
                println_fatal()
                return 1
            end
            writeln_both("")
        end

        kit_progress_step!("git")
        if !skip_hash_check
            if !local_git_clean(proj_dir)
                msg =
                    "⚠ Local working tree has uncommitted changes (this run may not match any git commit)"
                write_both("  ")
                print_progress_warn(msg)
                writeln_both("")
                writeln_both("  Omit --require-git to skip this check"; color=:light_black)
                writeln_both("")
            end

            if !isempty(host_names)
                writeln_both("Checking git hashes (--require-git)..."; color=:light_black)
                ok, mismatches, unverifiable = check_git_hashes(host_names, PROJECT_ROOT)
                writeln_both("")
                if !ok
                    # Fatal: always visible on the terminal (and kit log when open).
                    print_err("ERROR: "; bold=true)
                    if !isempty(mismatches)
                        println_fatal("Git hash mismatch on $(join(mismatches, ", "))")
                        println_fatal()
                        println_fatal("To re-deploy with git:")
                        println_fatal("  julia --project=. -m DistSSHKit setup --sync $(join(mismatches, " "))")
                        println_fatal()
                        println_fatal("Or re-deploy with rsync (after setup --delete if the path is nonempty):")
                        println_fatal("  julia --project=. -m DistSSHKit setup --rsync $(join(mismatches, " "))")
                        println_fatal()
                    end
                    if !isempty(unverifiable)
                        println_fatal("Git commit could not be verified on $(join(unverifiable, ", "))")
                        println_fatal("(remote tree may lack .git/ — e.g. after `setup --rsync`)")
                        println_fatal()
                        println_fatal("For rsync-deployed remotes, omit --require-git (the default).")
                        println_fatal()
                        println_fatal("Or use git-managed remotes:")
                        println_fatal("  julia --project=. -m DistSSHKit setup --clone HOST ...")
                        println_fatal("  julia --project=. -m DistSSHKit setup --sync HOST ...")
                        println_fatal()
                    end
                    println_fatal("Or omit --require-git and run without git parity.")
                    println_fatal()
                    return 1
                end
            end
        end

        kit_progress_step!("cleanup")
        cleanup_stale_workers!(hosts)

        kit_progress_step!("workers")
        if local_workers > 0 || !isempty(hosts)
            if !check_memory_capacity(local_workers, hosts, default_workers)
                return 1
            end
        end

        successful_hosts = add_drive_workers!(
            hosts, local_workers, default_workers, julia_exe, proj_dir, script_path,
        )
        wait_for_worker_connections!()
        drive_atexit_cleanup = register_worker_cleanup!(successful_hosts)

        kit_progress_step!("init")
        init_drive_workers!(proj_dir, explicit_package, _PATH_ANCHOR)
        sync_driver_to_workers!(script_path)
        run_prepare_workers!()

        empty!(ARGS)
        append!(ARGS, script_args)

        ENV["DISTRIBUTED_RUNNER"] = "1"
        skip_collect = get(ENV, "DISTRIBUTED_SKIP_COLLECT", "") == "1"
        sentinel_name = place_drive_sentinels!(successful_hosts, script_dir, skip_collect)

        kit_progress_step!("run")
        run_driver_script!(enable_log, drive_atexit_cleanup)

        kit_progress_step!("collect")
        collect_drive_results!(successful_hosts, script_dir, sentinel_name, skip_collect, _PATH_ANCHOR)
        progress_ok = true
        return 0
    finally
        kit_progress_done!(; ok=progress_ok)
    end
end
