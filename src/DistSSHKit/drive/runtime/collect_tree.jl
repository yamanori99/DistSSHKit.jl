"""
Recursively pull files under `local_root` from each host (**collect-missing** /
**collect-overwrite**).

- `merge=false`: skip relative paths that already exist locally.
- `merge=true`:  rsync the whole tree (overwrites same-named files).

Uses `DISTRIBUTED_REMOTE_PROJECT_ROOT` (via `remote_path_for_ssh_collect`) to map the local root to the correct path on each host.
Respects `--quiet` / `--progress` via kit printers (kit log still written when open).
"""
function drive_collect_tree(local_root::AbstractString, host_names::Vector{String}; merge::Bool=false)
    repo_root  = DistSSHKit.canonical_local_path(PROJECT_ROOT)
    local_root = DistSSHKit.canonical_local_path(local_root)
    transport = DistSSHKit._host_sync_rsync_transport()
    rsync_bin = DistSSHKit._host_sync_rsync_argv()

    print_header(merge ? "DistSSHKit collect-overwrite" : "DistSSHKit collect-missing")
    writeln_both("")
    writeln_field("Local root", display_path(local_root, _PATH_ANCHOR))
    writeln_field(
        "Mode",
        merge ? "full sync (same-named files updated when remote differs)" :
                "missing paths only (existing local files left unchanged)",
    )
    writeln_field("Hosts", join(host_names, ", "))
    writeln_both("")

    remote_root = remote_path_for_ssh_collect(local_root, repo_root)
    if remote_root != local_root
        writeln_field("Remote root", remote_root)
        writeln_both("")
    end

    ok = true
    for host in host_names
        write_both("  $host: ")
        try
            host_remote = ensure_remote_abs_path(host, remote_root)
            if host_remote === nothing
                writeln_both("(skip: cannot resolve remote root $(repr(remote_root)))")
                writeln_both("      hint: export DISTRIBUTED_REMOTE_PROJECT_ROOT=<abs path on SSH host>")
                continue
            end
            host_remote = host_remote::String
            pq = DistSSHKit._remote_shell_path_word(host_remote)
            if !success(pipeline(
                    DistSSHKit._host_sync_remote_shell_cmd(host, "test -d $pq");
                    stderr=devnull, stdout=devnull,
                ))
                writeln_both("(skip: no directory on host at $host_remote)")
                writeln_both("      hint: export DISTRIBUTED_REMOTE_PROJECT_ROOT=<repo root on SSH host>")
                continue
            end

            remote_files = collect_tree_remote_files_ssh(host, host_remote)
            if isempty(remote_files)
                writeln_both("(remote root empty or no files found)")
                continue
            end

            if merge
                # No `--mkpath`: macOS ships BSD rsync without that flag (GNU rsync 3.2.3+).
                rsync_cmd = Cmd(vcat(
                    rsync_bin,
                    ["-az", "-e", transport, string(host, ":", host_remote, "/"), local_root * "/"],
                ))
                run(pipeline(rsync_cmd; stderr=stderr))
                n = length(remote_files)
                print_ok("✓ (synced $n remote file$(n == 1 ? "" : "s"))")
                writeln_both("")
            else
                need = String[rel for (_, rel) in remote_files
                              if !isfile(joinpath(local_root, rel))]
                if isempty(need)
                    writeln_both("(nothing new — all remote files exist locally; use --collect-overwrite to replace)")
                    continue
                end
                sort!(need)
                # `--files-from` does not create parents on BSD rsync; pre-create (GNU rsync `--mkpath` unavailable).
                for rel in need
                    startswith(rel, "..") && continue
                    d = dirname(joinpath(local_root, rel))
                    !isempty(d) && mkpath(d)
                end
                DistSSHKit._run_rsync_files_from(
                    rsync_bin,
                    ["-az", "-e", transport],
                    string(host, ":", host_remote, "/"),
                    local_root * "/",
                    need,
                )
                n = length(need)
                print_ok("✓ ($n file$(n == 1 ? "" : "s"))")
                writeln_both("")
            end
        catch e
            ok = false
            print_progress_err("✗ $(sprint(showerror, e))")
            writeln_both("")
        end
    end
    writeln_both("")
    if !ok
        println_fatal("(some hosts failed; exit 1)")
    end
    return ok
end
