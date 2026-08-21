function print_size_report(
    all_hosts::Vector{String},
    hosts::Vector{String},
    samples::Dict{String,WorkerMemorySample},
    opts;
    show_peak::Bool=false,
)
    local_total, local_nproc = get_local_resources()
    host_resources = Dict{String,NamedTuple}(
        "localhost" => (total_gb=local_total, nproc=local_nproc)
    )
    for host in hosts
        host_resources[host] = (
            total_gb = something(get_remote_total_gb(host), 0.0),
            nproc    = something(get_remote_nproc(host), 1)
        )
    end

    per_worker_gb = per_worker_gb_dict(samples)
    plan = compute_worker_plan(
        all_hosts,
        hosts,
        per_worker_gb;
        mem_headroom=opts.mem_headroom,
        master_gb=opts.master_gb,
    )

    # Table stays on stdout under -q / --progress (not kit_println).
    host_col = 12
    if show_peak
        header = "Host           RAM      Cores   Baseline   Peak       Workers"
    else
        header = "Host           RAM      Cores   Per-worker  Workers"
    end
    println(header)
    println(rule_line(length(header)))
    for host in all_hosts
        res = host_resources[host]
        s = samples[host]
        n = host == "localhost" ? plan.local_workers : get(plan.remote_workers, host, 0)
        shown = host == "localhost" ? "masterhost" : host
        if show_peak
            println(
                "  $(lpad(shown, host_col))  $(round(res.total_gb, digits=1)) GB   $(res.nproc)      ",
                "$(s.baseline_gb) GB   $(s.peak_gb) GB   $n",
            )
        else
            println(
                "  $(lpad(shown, host_col))  $(round(res.total_gb, digits=1)) GB   $(res.nproc)      ",
                "$(effective_worker_gb(s)) GB     $n",
            )
        end
    end
    println()

    total = plan.local_workers + sum(values(plan.remote_workers); init=0)
    println("Total: $total workers")
    println()

    local_n = plan.local_workers
    remote_parts = ["$(h):$(plan.remote_workers[h])" for h in hosts if get(plan.remote_workers, h, 0) > 0]
    local_arg = local_n > 0 ? "masterhost:$local_n " : ""
    remote_arg = isempty(remote_parts) ? "" : join(remote_parts, " ") * " "
    println("Command template:")
    worker_args = "$(local_arg)$(remote_arg)"
    if isempty(worker_args)
        println("  julia --project=. -m DistSSHKit drive <script.jl> <args>")
    else
        println("  julia --project=. -m DistSSHKit drive \\")
        println("    $(rstrip(worker_args)) \\")
        println("    <script.jl> <args>")
    end
    println(rule_line())
end

function resolve_worker_memory_samples(
    project::AbstractString,
    all_hosts::Vector{String},
    hosts::Vector{String},
    opts,
)::Union{Dict{String,WorkerMemorySample},Nothing}
    if opts.gb_per_worker !== nothing
        g = Float64(opts.gb_per_worker)
        samples = Dict{String,WorkerMemorySample}()
        for h in all_hosts
            samples[h] = WorkerMemorySample(g, g)
        end
        kit_println("Per-worker: $(opts.gb_per_worker) GB (manual)")
        return samples
    end

    if opts.probe !== nothing
        kit_println("Measuring per-worker memory (package load + probe)...")
        kit_println("  Probe: $(opts.probe)")
    else
        kit_println("Measuring per-worker memory (package load)...")
    end
    kit_println()
    measured = measure_rss(
        project,
        hosts;
        include_local=opts.include_local,
        probe=opts.probe,
        hint_surface=:cli,
    )
    if isempty(measured)
        print_err("Measurement failed. Use --gb-per-worker N.")
        println()
        return nothing
    end
    failed = [h for h in all_hosts if !haskey(measured, h)]
    if !isempty(failed)
        print_warn("  Connection failed: $(join(failed, ", "))\n")
    end
    samples = Dict{String,WorkerMemorySample}()
    for h in all_hosts
        if haskey(measured, h)
            s = measured[h]
            samples[h] = s
            kit_print("  $h: ")
            if opts.probe !== nothing
                print_ok("baseline $(s.baseline_gb) GB, peak $(s.peak_gb) GB")
            else
                print_ok("$(s.baseline_gb) GB")
            end
            kit_println()
        else
            fb = WORKER_MEMORY_GB_FALLBACK
            samples[h] = WorkerMemorySample(fb, fb)
            print_warn("  $h: $fb GB (probe failed, using default)\n")
        end
    end
    return samples
end
