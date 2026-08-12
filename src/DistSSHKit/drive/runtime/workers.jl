"""Per-worker project directory for `Pkg.activate` (`myid` → path on that process)."""
const RUNNER_WORKER_PROJECT_DIRS = Dict{Int,String}()
"""Per-worker driver script path for `include` (`myid` → path on that process)."""
const RUNNER_WORKER_SCRIPT_PATHS = Dict{Int,String}()

function _register_drive_workers!(
    before::Set{Int},
    proj_path::String,
    script_path::String,
)
    for w in workers()
        if w ∉ before
            RUNNER_WORKER_PROJECT_DIRS[w] = proj_path
            RUNNER_WORKER_SCRIPT_PATHS[w] = script_path
        end
    end
    return nothing
end

function _skip_global_worker_pkill()::Bool
    return get(ENV, "DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL", "") == "1"
end

function _pkill_stale_julia_workers_local!()
    DistSSHKit._pkill_local_julia_workers!()
end

function _pkill_stale_julia_workers_remote!(host_name::String)::Bool
    return DistSSHKit._pkill_remote_julia_workers!(host_name)
end

function cleanup_stale_workers!(hosts)
    if _skip_global_worker_pkill()
        return
    end
    writeln_both("Cleaning up stale workers..."; color=:light_black)

    _pkill_stale_julia_workers_local!()
    write_both("  localhost: ")
    print_ok("✓")
    writeln_both("")

    for (host_name, _) in hosts
        write_both("  $host_name: ")
        if _pkill_stale_julia_workers_remote!(host_name)
            print_ok("✓")
        else
            print_progress_warn("(SSH unreachable)")
        end
        writeln_both("")
    end
    writeln_both("")
end

function add_drive_workers!(
    hosts,
    local_workers::Int,
    default_workers,
    julia_exe,
    proj_dir::String,
    script_path::String,
)::Vector{String}
    empty!(RUNNER_WORKER_PROJECT_DIRS)
    empty!(RUNNER_WORKER_SCRIPT_PATHS)
    script_path = abspath(String(script_path))
    writeln_both("Adding workers..."; color=:light_black)

    successful_hosts = String[]

    if local_workers > 0
        write_both("  localhost ($local_workers workers): ")
        try
            before = Set(workers())
            addprocs(local_workers; exeflags=`--project=$proj_dir`, topology=:master_worker)
            _register_drive_workers!(before, proj_dir, script_path)
            print_ok("✓")
            writeln_both("")
        catch e
            print_progress_err("✗ ($e)")
            writeln_both("")
        end
    else
        writeln_both("  localhost: master only (use l:N or local:N for local workers)")
    end

    sshflags_cmd = Cmd(ssh_opts())

    for (host_name, host_workers_spec) in hosts
        host_julia = julia_exe
        if host_julia === nothing
            write_both("  $host_name: detecting Julia... ")
            host_julia = detect_julia_path(host_name)
            if host_julia === nothing
                print_progress_err("✗ (Julia not found)")
                writeln_both("")
                continue
            end
            print_info("found at $host_julia")
            writeln_both("")
            write_both("  ")
        end

        host_workers = something(host_workers_spec, default_workers, 1)

        repo_ra = DistSSHKit.canonical_local_path(PROJECT_ROOT)
        script_dir = dirname(script_path)
        remote_dir = resolve_host_path_abs(host_name, script_dir, repo_ra)
        remote_proj = resolve_host_path_abs(host_name, proj_dir, repo_ra)
        remote_script = resolve_host_path_abs(host_name, script_path, repo_ra)
        if remote_dir === nothing || remote_proj === nothing || remote_script === nothing
            write_both("$host_name ($host_workers workers): ")
            missing = remote_dir === nothing ? remote_path_for_ssh_collect(script_dir, repo_ra) :
                      remote_proj === nothing ? remote_path_for_ssh_collect(proj_dir, repo_ra) :
                      remote_path_for_ssh_collect(script_path, repo_ra)
            print_progress_err("✗ (remote path not found: $missing)")
            writeln_both("")
            writeln_both("    hint: julia --project=. -m DistSSHKit setup --rsync $host_name")
            writeln_both("          julia --project=. -m DistSSHKit setup --instantiate $host_name")
            writeln_both("           or export DISTRIBUTED_REMOTE_PROJECT_ROOT=<abs path on host>")
            continue
        end

        deps_err = DistSSHKit.probe_remote_project_deps(
            host_name, remote_proj; julia_path=String(host_julia),
        )
        if deps_err !== nothing
            write_both("$host_name ($host_workers workers): ")
            print_progress_err("✗ ($deps_err)")
            writeln_both("")
            writeln_both("    hint: julia --project=. -m DistSSHKit setup --instantiate $host_name")
            continue
        end

        write_both("$host_name ($host_workers workers): ")
        try
            before = Set(workers())
            # Default tunnel=true. Set DISTSSHKIT_SSH_TUNNEL=0 to disable.
            # Machine must be user@host: Distributed prefixes \$USER otherwise and
            # overrides SSH config User (Host aliases then look like "No free port?").
            use_tunnel = get(ENV, "DISTSSHKIT_SSH_TUNNEL", "1") != "0"
            machine = DistSSHKit.ssh_addprocs_machine(host_name)
            addprocs([(machine, host_workers)];
                     exename=`$host_julia`,
                     sshflags=sshflags_cmd,
                     dir=remote_dir,
                     tunnel=use_tunnel,
                     topology=:master_worker,
                     exeflags=`--project=$remote_proj`)
            _register_drive_workers!(before, remote_proj, remote_script)
            print_ok("✓")
            writeln_both("")
            push!(successful_hosts, host_name)
        catch e
            print_progress_err("✗")
            writeln_both("")
            if e isa CompositeException
                for (i, ex) in enumerate(e.exceptions)
                    actual_ex = ex isa TaskFailedException ? ex.task.result : ex
                    writeln_both("    Error $i: $(typeof(actual_ex))")
                    msg = sprint(showerror, actual_ex)
                    first_line = first(split(msg, '\n'))
                    writeln_both("    $first_line")
                end
            else
                writeln_both("    $(sprint(showerror, e))")
            end
        end
    end

    writeln_both("")
    writeln_field("Workers", string(nworkers()))
    writeln_both("")

    # Alone, Julia reports nworkers()==1 (the master). Fail when nothing joined.
    nprocs() <= 1 && error("No workers available. Check SSH connectivity.")

    return successful_hosts
end

function wait_for_worker_connections!()
    _init_delay = tryparse(Float64, get(ENV, "DISTRIBUTED_INIT_DELAY_SEC", "5"))
    if _init_delay !== nothing && _init_delay > 0
        label = "Waiting for worker connections ($(round(_init_delay, digits=1))s)... "
        DistSSHKit.kit_spin!(label) do
            sleep(_init_delay)
            return nothing
        end
        print_ok("✓")
        writeln_both("")
    end
end

function register_worker_cleanup!(successful_hosts::Vector{String})
    cleanup_registered = Ref(false)
    function drive_atexit_cleanup()
        cleanup_registered[] && return
        cleanup_registered[] = true

        if nworkers() > 0
            try
                @everywhere stop_heartbeat_monitor()
                sleep(0.5)
            catch
            end
        end

        if nworkers() > 0
            try
                rmprocs(workers(); waitfor=5.0)
            catch
            end
        end

        for host in successful_hosts
            _skip_global_worker_pkill() && continue
            _pkill_stale_julia_workers_remote!(host)
        end
    end
    atexit(drive_atexit_cleanup)
    return drive_atexit_cleanup
end
