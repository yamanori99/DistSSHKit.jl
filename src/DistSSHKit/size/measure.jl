# Per-host RSS probe for size / size!.
# Remotecalls use `Core.eval` on worker `Main` so workers need not load DistSSHKit.

"""Resolve a size `--probe` script path under `project` (absolute paths unchanged)."""
function resolve_size_probe_path(
    project::AbstractString,
    probe::AbstractString,
)::String
    p = strip(String(probe))
    isempty(p) && throw(ArgumentError("size probe path is empty"))
    return isabspath(p) ? canonical_local_path(p) : canonical_local_path(joinpath(project, p))
end

"""Quoted probe: activate, optional package load, baseline RSS, optional include, peak RSS."""
function _size_probe_rss_expr(
    path::String,
    pkg_name::Union{Nothing,String},
    probe_path::Union{Nothing,String},
)
    load_pkg = if pkg_name === nothing
        :(nothing)
    else
        pkg_sym = Symbol(pkg_name)
        quote
            try
                @eval using $pkg_sym
            catch
            end
        end
    end
    run_probe = if probe_path === nothing
        :(nothing)
    else
        quote
            include($probe_path)
        end
    end
    return quote
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
        using Pkg
        Pkg.activate($path; io=devnull)
        $load_pkg
        baseline = Sys.maxrss()
        $run_probe
        peak = Sys.maxrss()
        (baseline, peak)
    end
end

"""
    measure_rss(project, hosts; include_local=false, probe=nothing, hint_surface=:api)

Add one probe worker per host, load the project package, measure RSS.

Returns `Dict(hostname => WorkerMemorySample)`. `baseline_gb` is after package
load; when `probe` is a script path (absolute or relative to `project`), that
file is `include`d on the worker and `peak_gb` is measured afterward. Without a
probe, `peak_gb == baseline_gb`.

Uses the same remote path resolution as drive `addprocs`. Suggestions should use
`effective_worker_gb` / `per_worker_gb_dict`.
"""
function measure_rss(
    project::AbstractString,
    hosts::Vector{String};
    include_local::Bool=false,
    probe::Union{Nothing,AbstractString}=nothing,
    hint_surface::Symbol=:api,
)::Dict{String,WorkerMemorySample}
    proj = canonical_local_path(project)
    probe_local = probe === nothing ? nothing : resolve_size_probe_path(proj, probe)
    if probe_local !== nothing && !isfile(probe_local)
        throw(ArgumentError(explain_size_probe_not_found(probe_local; surface=hint_surface)))
    end

    worker_to_host = Dict{Int,String}()
    worker_project = Dict{Int,String}()
    worker_probe = Dict{Int,Union{Nothing,String}}()

    try
        return _measure_rss!(
            proj, hosts, include_local, probe_local,
            worker_to_host, worker_project, worker_probe,
        )
    finally
        _rmprocs_measure_probes!(worker_to_host)
    end
end

"""Remove only probe pids this `measure_rss` added. Never `rmprocs(workers())`."""
function _rmprocs_measure_probes!(worker_to_host::Dict{Int,String})
    ids = Int[w for w in keys(worker_to_host) if w != 1 && w in workers()]
    isempty(ids) && return
    try
        rmprocs(ids; waitfor=2.0)
    catch
    end
    return nothing
end

function _measure_rss!(
    proj::String,
    hosts::Vector{String},
    include_local::Bool,
    probe_local::Union{Nothing,String},
    worker_to_host::Dict{Int,String},
    worker_project::Dict{Int,String},
    worker_probe::Dict{Int,Union{Nothing,String}},
)::Dict{String,WorkerMemorySample}
    if include_local
        try
            local_proj = something(resolve_host_project_abs("localhost", proj), proj)
            before = Set(workers())
            addprocs(1; exeflags=`--project=$local_proj`, topology=:master_worker)
            added = setdiff(Set(workers()), before)
            if !isempty(added)
                wid = first(added)
                worker_to_host[wid] = "localhost"
                worker_project[wid] = local_proj
                worker_probe[wid] = probe_local
            end
        catch e
            @warn "Local worker failed: $e"
        end
    end

    if !isempty(hosts)
        sshflags_cmd = Cmd(ssh_opts())
        n_hosts = length(hosts)
        detected = Vector{Union{Nothing,String}}(undef, n_hosts)
        map_host_jobs(hosts) do i, host
            detected[i] = detect_julia_path(host)
        end
        for i in 1:n_hosts
            host = hosts[i]
            julia_exe = detected[i]
            if julia_exe === nothing
                @warn "Worker on $host failed: Julia not found (auto-detect)"
                continue
            end
            remote_proj = resolve_host_project_abs(host, proj)
            if remote_proj === nothing
                @warn "Worker on $host failed: remote project path not found" proj=proj
                continue
            end
            remote_probe = nothing
            if probe_local !== nothing
                remote_probe = resolve_host_path_abs(host, probe_local, proj)
                if remote_probe === nothing
                    @warn "Worker on $host failed: size probe path not found on host" probe=probe_local
                    continue
                end
            end
            try
                use_tunnel = get(ENV, "DISTSSHKIT_SSH_TUNNEL", "1") != "0"
                machine = ssh_addprocs_machine(host)
                before = Set(workers())
                addprocs([(machine, 1)];
                         exename=`$julia_exe`,
                         sshflags=sshflags_cmd,
                         dir=remote_proj,
                         tunnel=use_tunnel,
                         topology=:master_worker,
                         exeflags=`--project=$remote_proj`)
                added = setdiff(Set(workers()), before)
                isempty(added) && continue
                wid = first(added)
                worker_to_host[wid] = host
                worker_project[wid] = remote_proj
                worker_probe[wid] = remote_probe
            catch e
                @warn "Worker on $host failed: $e"
            end
        end
    end

    isempty(worker_to_host) && return Dict{String,WorkerMemorySample}()

    pkg_name = project_package_name(proj)
    samples = Dict{String,WorkerMemorySample}()

    # One precompile per host (first worker) to avoid races.
    host_first = Dict{String,Int}()
    for (w, h) in worker_to_host
        haskey(host_first, h) || (host_first[h] = w)
    end

    for (_, wid) in host_first
        path = worker_project[wid]
        try
            remotecall_fetch(Core.eval, wid, Main, quote
                ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
                using Pkg
                Pkg.activate($path; io=devnull)
                Pkg.precompile(; io=devnull)
                nothing
            end)
        catch
        end
    end

    for (wid, host) in worker_to_host
        path = worker_project[wid]
        probe_on_host = worker_probe[wid]
        try
            baseline_rss, peak_rss = remotecall_fetch(
                Core.eval, wid, Main,
                _size_probe_rss_expr(path, pkg_name, probe_on_host),
            )
            baseline_gb = rss_bytes_to_worker_gb(Int(baseline_rss))
            peak_gb = rss_bytes_to_worker_gb(Int(peak_rss))
            samples[host] = WorkerMemorySample(baseline_gb, peak_gb)
        catch
            fb = WORKER_MEMORY_GB_FALLBACK
            samples[host] = WorkerMemorySample(fb, fb)
        end
    end

    return samples
end
