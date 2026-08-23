using .DistSSHKit:
    DEFAULT_MEM_HEADROOM,
    PARENT_HOST_NAME,
    WORKER_MEMORY_GB_FALLBACK,
    get_local_git_hash,
    get_remote_git_hash,
    get_remote_total_gb,
    print_ok,
    print_progress_err,
    print_progress_warn,
    print_warn,
    println_fatal,
    rss_bytes_to_worker_gb,
    write_both,
    writeln_both

# Runner-only preflight checks (git parity, memory capacity).

function estimate_worker_memory_gb()
    try
        rss_bytes = Sys.maxrss()
        rss_bytes > 0 && return rss_bytes_to_worker_gb(rss_bytes)
    catch
    end
    return WORKER_MEMORY_GB_FALLBACK
end

function estimate_available_gb()
    total = Sys.total_memory() / 1024^3
    free = Sys.free_memory() / 1024^3
    return (total, max(free, total * 0.5))
end

function check_memory_capacity(
    local_workers::Int,
    hosts::Vector{Tuple{String,Union{Int,Nothing}}},
    default_workers::Union{Int,Nothing};
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
)::Bool
    frac = Float64(mem_headroom)
    per_worker = estimate_worker_memory_gb()
    r(x) = round(x, digits=1)
    writeln_both("Checking memory capacity...")
    writeln_both("  Per-worker estimate: $(round(per_worker, digits=2))GB")
    warnings = String[]

    function check_host(label::String, n_workers::Int, total_gb)
        if total_gb === nothing
            writeln_both("  $label: (memory check failed)")
            return
        end
        avail = total_gb * frac
        estimated = n_workers * per_worker
        max_w = max(1, floor(Int, avail / per_worker))
        pct = round(Int, frac * 100)
        if estimated > avail
            push!(warnings, "  $label: $(n_workers) × $(r(per_worker))GB = $(r(estimated))GB > $(r(avail))GB ($(pct)% of $(r(total_gb))GB)")
            write_both("  $label: $(r(total_gb))GB, $(n_workers) workers → ")
            print_progress_warn("⚠ (max ~$(max_w))")
            writeln_both("")
        else
            write_both("  $label: $(r(total_gb))GB, $(n_workers) workers → ")
            print_ok("✓")
            writeln_both("")
        end
    end

    if local_workers > 0
        total, _ = estimate_available_gb()
        check_host(PARENT_HOST_NAME, local_workers + 1, total)
    end

    host_totals = Dict{String,Int}()
    for (host_name, host_workers_spec) in hosts
        n = something(host_workers_spec, default_workers, 1)
        host_totals[host_name] = get(host_totals, host_name, 0) + n
    end

    for (host_name, host_workers) in host_totals
        check_host(host_name, host_workers, get_remote_total_gb(host_name))
    end
    writeln_both("")

    if !isempty(warnings)
        print_warn("WARNING: "; bold=true)
        println_fatal("Memory pressure detected!")
        println_fatal()
        for w in warnings
            print_warn(w * "\n")
        end
        println_fatal()
        println_fatal("Consider reducing worker count.")
        println_fatal()
        DistSSHKit.kit_confirm("Continue anyway? [y/N]: ") || begin
            println_fatal("Aborted.")
            return false
        end
        println_fatal()
    end
    return true
end

function check_git_hashes(hosts::Vector{String}, proj_dir::String)
    remote_root = DistSSHKit.resolve_remote_project_root(proj_dir)
    env_remote = strip(get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", ""))

    local_hash = get_local_git_hash(proj_dir)
    if local_hash === nothing
        write_both("  ")
        print_progress_warn("⚠ Could not get local git hash (not a git repo?)")
        writeln_both("")
        if !isempty(hosts)
            writeln_both("  Remote git parity cannot be verified without a local git commit.")
            writeln_both("")
            return false, String[], copy(hosts)
        end
        return true, String[], String[]
    end

    writeln_both("  Local: $(local_hash[1:8])...")
    if !isempty(hosts) || !isempty(env_remote)
        writeln_both("  Remote project root: $remote_root")
    end

    mismatches = String[]
    unverifiable = String[]
    for host in hosts
        remote_hash = get_remote_git_hash(host, remote_root)
        if remote_hash === nothing
            write_both("  $host: ")
            print_progress_err("✗ Could not get git hash (not a git repo?)")
            writeln_both("")
            push!(unverifiable, host)
        elseif remote_hash != local_hash
            write_both("  $host: ")
            print_progress_err("✗ $(remote_hash[1:8])... (MISMATCH)")
            writeln_both("")
            push!(mismatches, host)
        else
            write_both("  $host: ")
            print_ok("✓ $(remote_hash[1:8])...")
            writeln_both("")
        end
    end

    ok = isempty(mismatches) && isempty(unverifiable)
    return ok, mismatches, unverifiable
end
