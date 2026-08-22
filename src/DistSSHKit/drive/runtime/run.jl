# Core drive execution after argv parse (shared by CLI `drive_main` and API `drive!`).

"""
    run_drive_parsed!(parsed; original_args=String[], resolved_output_dir=nothing, resolved_log_dir=nothing) -> Cint

Run a driver from a `parse_drive_args`-shaped NamedTuple. Mutates `ARGS` to
`script_args` while the driver runs; callers should restore `ARGS` in `finally`.

`resolved_output_dir` / `resolved_log_dir` are optional `Ref{Union{Nothing,String}}`
out-params: when a real run happens (script found, past argv-only branches),
they are filled with the directory actually used — `resolve_drive_output_dir`
(same value `collect_drive_results!` reports as `Results:`) and
`resolve_drive_log_dir` (same value `init_log_file` writes to) respectively.
Callers (`drive!`) use these to report an accurate `DriveResult.output_dir` /
`.log_dir` even when the caller did not pass `output_dir=` / `log_dir=` explicitly.
"""
function run_drive_parsed!(
    parsed;
    original_args::Vector{String}=String[],
    resolved_output_dir::Union{Nothing,Base.RefValue{Union{Nothing,String}}}=nothing,
    resolved_log_dir::Union{Nothing,Base.RefValue{Union{Nothing,String}}}=nothing,
    resolved_hosts::Union{Nothing,Base.RefValue{Vector{DistSSHKit.HostRunResult}}}=nothing,
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
            strict=parsed.require_all_hosts,
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
    require_all_hosts = parsed.require_all_hosts

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
    release_output_dir_lock = DistSSHKit.kit_output_dir_lock!(DistSSHKit.resolve_drive_output_dir(script_dir))
    try
        return _run_drive_parsed_locked!(
            parsed, output_dir, script_path, script_dir, proj_dir, script_args,
            enable_log, log_dir, original_args, host_names, hosts, local_workers,
            default_workers, julia_exe, skip_hash_check, explicit_package,
            require_all_hosts, resolved_output_dir, resolved_log_dir, resolved_hosts,
        )
    finally
        release_output_dir_lock()
    end
end

function _run_drive_parsed_locked!(
    parsed, output_dir, script_path, script_dir, proj_dir, script_args,
    enable_log, log_dir, original_args, host_names, hosts, local_workers,
    default_workers, julia_exe, skip_hash_check, explicit_package,
    require_all_hosts, resolved_output_dir, resolved_log_dir, resolved_hosts,
)::Cint
    include(script_path)
    if isdefined(Main, :init_output_dir!)
        @invokelatest Main.init_output_dir!(script_args)
    end

    if enable_log
        init_log_file(DistSSHKit.resolve_drive_log_dir(log_dir, script_dir); prefix="drive", path_anchor=_PATH_ANCHOR)
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
    # Set once `add_drive_workers!` returns (registers rmprocs-at-atexit for
    # whatever joined). `finally` below always calls it so local/SSH workers
    # from *this* run are torn down before `run_drive_parsed!` returns, not
    # just at Julia process exit — callers (`drive!`, `execute!`) can run more
    # than once per process (tests; long-lived services).
    drive_atexit_cleanup = nothing
    kit_progress_begin!("drive"; steps=progress_steps, kind=:drive)
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
                print_warn(msg)
                println_fatal()
                println_fatal("  Omit --require-git to skip this check")
                println_fatal()
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
        if (local_workers > 0 || !isempty(hosts)) &&
                !check_memory_capacity(local_workers, hosts, default_workers)
            return 1
        end

        successful_hosts = add_drive_workers!(
            hosts, local_workers, default_workers, julia_exe, proj_dir, script_path,
        )
        # Register before the `require_all_hosts` check below: that branch can
        # `return 1` with workers already joined, and `finally` must still
        # reach a non-`nothing` `drive_atexit_cleanup` to tear them down.
        drive_atexit_cleanup = register_worker_cleanup!(successful_hosts)
        if require_all_hosts && !isempty(hosts)
            missing = String[h[1] for h in hosts if !(h[1] in successful_hosts)]
            missing = unique(missing)
            if !isempty(missing)
                print_err("ERROR: "; bold=true)
                println_fatal("required hosts did not join: $(join(missing, ", "))")
                println_fatal("Omit --require-all-hosts for best-effort (the default).")
                return 1
            end
        end
        wait_for_worker_connections!()

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
        collect_ok, collect_hosts = collect_drive_results!(successful_hosts, script_dir, sentinel_name, skip_collect, _PATH_ANCHOR)
        resolved_hosts !== nothing && (resolved_hosts[] = collect_hosts)
        if require_all_hosts && !collect_ok
            progress_ok = false
            return 1
        end
        progress_ok = true
        return 0
    finally
        if resolved_output_dir !== nothing
            resolved_output_dir[] = DistSSHKit.resolve_drive_output_dir(script_dir)
        end
        if resolved_log_dir !== nothing
            resolved_log_dir[] = enable_log ? DistSSHKit.resolve_drive_log_dir(log_dir, script_dir) : nothing
        end
        kit_progress_done!(; ok=progress_ok)
        # `nothing` when no workers were ever added (early `return` above
        # `add_drive_workers!`). Otherwise idempotent (guarded by a `Ref`
        # inside) — a harmless no-op if `atexit` already ran it.
        drive_atexit_cleanup !== nothing && drive_atexit_cleanup()
    end
end
