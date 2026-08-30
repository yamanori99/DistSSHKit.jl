function place_drive_sentinels!(successful_hosts::Vector{String}, script_dir::String, skip_collect::Bool)::String
    (skip_collect || isempty(successful_hosts)) && return ""
    sentinel_name = ".drive_sentinel_$(getpid())_$(Dates.format(now(), "yyyymmddTHHMMSS"))"
    repo_ra = DistSSHKit.canonical_local_path(PROJECT_ROOT)
    collect_roots_sentinel = distributed_collect_root_dirs(script_dir, repo_ra)
    for local_rd in collect_roots_sentinel
        _early_local = DistSSHKit.canonical_local_path(local_rd)
        for host in unique(successful_hosts)
            try
                remote_early = remote_path_for_ssh_collect(_early_local, repo_ra)
                remote_early_abs = ensure_remote_abs_path(host, remote_early)
                if remote_early_abs === nothing
                    print_warn("sentinel: cannot resolve collect root on $host")
                    continue
                end
                remote_early_abs = remote_early_abs::String
                pq = DistSSHKit._remote_shell_path_word(remote_early_abs)
                sn = DistSSHKit._remote_shell_path_word(joinpath(remote_early_abs, sentinel_name))
                run(pipeline(DistSSHKit._host_sync_remote_shell_cmd(host, "mkdir -p $pq"),
                    stdout=devnull, stderr=devnull))
                run(pipeline(DistSSHKit._host_sync_remote_shell_cmd(host, "touch $sn"),
                    stdout=devnull, stderr=devnull))
            catch e
                DistSSHKit._rethrow_missing_host_tool(e)
                print_warn("sentinel on $host: $(sprint(showerror, e))")
            end
        end
    end
    return sentinel_name
end

function run_driver_script!(enable_log::Bool, drive_atexit_cleanup)
    writeln_both("Running script..."; color=:light_black)
    writeln_both("")
    call_main = () -> begin
        Base.invokelatest() do
            if isdefined(Main, :main)
                main_fn = getfield(Main, :main)
                if main_fn isa Function
                    Base.invokelatest(Base.inferencebarrier(main_fn))
                end
            end
        end
    end
    try
        if enable_log && LOG_FILE_HANDLE[] !== nothing
            orig_stdout = stdout
            log_io = LOG_FILE_HANDLE[]
            linebuf = UInt8[]
            rd, wr = redirect_stdout()
            reader = @async begin
                try
                    while true
                        data = readavailable(rd)
                        if !isempty(data)
                            # `:verbose`: live on the terminal. `:progress`: capture
                            # and replay after the bar so the TTY stays a single line.
                            # `:quiet`: kit log only.
                            if DistSSHKit.kit_output_detail()
                                write(orig_stdout, data)
                            elseif DistSSHKit.kit_output_progress()
                                DistSSHKit._append_job_stdout_capture!(data)
                            end
                            for b in data
                                if b == 0x0d
                                    empty!(linebuf)
                                elseif b == 0x0a
                                    write(log_io, linebuf)
                                    write(log_io, b)
                                    flush(log_io)
                                    empty!(linebuf)
                                else
                                    push!(linebuf, b)
                                end
                            end
                        end
                        # NOTE: no `yield()` here on an empty read — `readavailable` already
                        # blocks until data or close, so spin-yielding instead of letting it
                        # block starves libuv's notice of `wr` closing (observed ~30s stalls).
                        isempty(data) && (eof(rd) || !isopen(wr)) && break
                    end
                    if !isempty(linebuf)
                        write(log_io, linebuf)
                        flush(log_io)
                    end
                catch e
                    isa(e, Base.IOError) || rethrow()
                end
            end
            try
                call_main()
            finally
                flush(stdout)
                close(wr)
                # `rd` normally reaches EOF once `wr` closes, but local worker processes
                # (spawned via `addprocs`) inherit our stdout fd and keep the underlying
                # pipe open until they exit, so EOF may never arrive here. All real script
                # output is already flushed to `rd` by this point (readavailable drains it
                # as it's written), so a short grace period is enough before we force-close.
                wait_ok = @async wait(reader)
                for _ in 1:20
                    istaskdone(wait_ok) && break
                    sleep(0.05)
                end
                if !istaskdone(wait_ok)
                    close(rd)
                    wait(reader)
                end
                redirect_stdout(orig_stdout)
            end
        else
            call_main()
        end
    catch e
        if e isa InterruptException
            writeln_both("\nInterrupted. Cleaning up workers...")
            drive_atexit_cleanup()
            exit(130)
        end
        rethrow()
    end
end

function collect_drive_results!(
    successful_hosts::Vector{String},
    script_dir::String,
    sentinel_name::String,
    skip_collect::Bool,
    path_anchor::String,
)
    results_dir = DistSSHKit.resolve_drive_output_dir(script_dir)

    if isempty(successful_hosts)
        writeln_both("")
        writeln_field("Results", display_path(results_dir, path_anchor))
        return true, DistSSHKit.HostRunResult[]
    end

    writeln_both("")
    if skip_collect
        writeln_both("Results saved locally (no remote collection needed).")
        writeln_field("Results", display_path(results_dir, path_anchor))
        return true, [DistSSHKit.HostRunResult(h, true) for h in unique(successful_hosts)]
    end

    collect_roots = distributed_collect_root_dirs(script_dir, DistSSHKit.canonical_local_path(PROJECT_ROOT))
    for local_rd in collect_roots
        mkpath(local_rd)
    end
    writeln_both("Collecting results from remote hosts..."; color=:light_black)
    repo_ra = DistSSHKit.canonical_local_path(PROJECT_ROOT)
    hosts_u = unique(successful_hosts)
    n_hosts = length(hosts_u)
    totals = zeros(Int, n_hosts)
    errs = Vector{Any}(undef, n_hosts)
    fill!(errs, nothing)

    DistSSHKit.map_host_jobs(hosts_u) do i, host
        DistSSHKit._drive_host_span!(host, "collect", :running)
        total_for_host = 0
        host_err = nothing
        try
            ssh_cmd = DistSSHKit._host_sync_rsync_transport()
            rsync_bin = DistSSHKit._host_sync_rsync_argv()
            for local_rd in collect_roots
                local_abs = DistSSHKit.canonical_local_path(local_rd)
                remote_rd_collect = remote_path_for_ssh_collect(local_abs, repo_ra)
                remote_rd_abs = ensure_remote_abs_path(host, remote_rd_collect)
                if remote_rd_abs === nothing
                    host_err === nothing && (host_err = ErrorException(
                        "cannot resolve remote collect root on $host",
                    ))
                    continue
                end
                remote_rd_abs = remote_rd_abs::String
                remote_sentinel = joinpath(remote_rd_abs, sentinel_name)
                try
                    remote_find_raw = try
                        pq = DistSSHKit._remote_shell_path_word(remote_rd_abs)
                        sq = DistSSHKit._remote_shell_path_word(remote_sentinel)
                        nq = DistSSHKit._remote_shell_path_word(sentinel_name)
                        strip(
                            read(
                                pipeline(
                                    DistSSHKit._host_sync_remote_shell_cmd(
                                        host,
                                        "find $pq -type f -newer $sq ! -name $nq -print",
                                    );
                                    stderr=devnull,
                                ),
                                String,
                            ),
                        )
                    catch e
                        DistSSHKit._rethrow_missing_host_tool(e)
                        throw(ErrorException(
                            "collect find -newer on $host: $(sprint(showerror, e))",
                        ))
                    end
                    rroot = String(rstrip(String(remote_rd_abs), '/'))
                    rel_lines = String[]
                    for line in split(remote_find_raw, '\n')
                        lp = strip(String(line))
                        isempty(lp) && continue
                        rel = if startswith(lp, rroot * "/")
                            lp[(length(rroot) + 2):end]
                        else
                            continue
                        end
                        isempty(rel) && continue
                        startswith(rel, "..") && continue
                        push!(rel_lines, rel)
                    end

                    if !isempty(rel_lines)
                        uniq = unique(rel_lines)
                        DistSSHKit._run_rsync_files_from(
                            rsync_bin,
                            ["-az", "-e", ssh_cmd],
                            string(host, ":", remote_rd_abs, "/"),
                            local_abs * "/",
                            uniq,
                        )
                        total_for_host += length(uniq)
                    end
                catch e
                    host_err === nothing && (host_err = e)
                finally
                    try
                        rq = DistSSHKit._remote_shell_path_word(remote_sentinel)
                        run(pipeline(
                            DistSSHKit._host_sync_remote_shell_cmd(host, "rm -f $rq"),
                            stdout=devnull, stderr=devnull,
                        ))
                    catch e
                        DistSSHKit._rethrow_missing_host_tool(e)
                    end
                end
            end
        catch e
            host_err === nothing && (host_err = e)
        finally
            DistSSHKit._drive_host_span!(
                host, "collect", host_err === nothing ? :ok : :fail,
            )
        end
        totals[i] = total_for_host
        errs[i] = host_err
    end

    collect_ok = true
    host_results = Vector{DistSSHKit.HostRunResult}(undef, n_hosts)
    for i in 1:n_hosts
        host = hosts_u[i]
        total_for_host = totals[i]
        host_err = errs[i]
        write_both("  $host: ")
        if host_err !== nothing
            collect_ok = false
            print_progress_err("✗ ($host_err)")
        elseif total_for_host == 0
            print_progress_warn("(nothing to collect)")
        else
            print_ok("✓ ($total_for_host file$(total_for_host == 1 ? "" : "s"))")
        end
        writeln_both("")
        host_results[i] = DistSSHKit.HostRunResult(host, host_err === nothing, host_err)
    end
    coll_disp = join(
        (display_path(String(p), path_anchor) for p in collect_roots),
        ", ",
    )
    writeln_field("Results", coll_disp)
    return collect_ok, host_results
end
