using Pkg

function _drive_worker_activate!(path::String)
    Pkg.activate(path; io=devnull)
    return nothing
end

function _drive_worker_include!(path::String)
    Base.include(Main, path)
    return nothing
end

"""
    activate_drive_project!(proj_dir)

Activate the host application project on the master process before the driver
script is first `include`d. Workers are activated separately during init.
"""
function activate_drive_project!(proj_dir::String)
    isdir(proj_dir) || return
    isfile(joinpath(proj_dir, "Project.toml")) || return
    try
        Pkg.activate(proj_dir; io=devnull)
    catch
    end
end

"""
    sync_driver_to_workers!(script_path)

Re-`include` the driver on every process after the project package has been
loaded. This is the kit's named "get code onto workers" step: top-level helper
functions in the driver are available on workers for `pmap`, and definitions on
the master are compiled in the post-package-load world (Julia 1.12+ world age).

Drivers must not run side effects at top level (only function definitions).
`init_output_dir!` is invoked separately on the master before workers start.
"""
function sync_driver_to_workers!(script_path::String)
    sp = abspath(String(script_path))
    write_both("  Syncing driver to workers... ")
    flush(stdout)
    try
        for w in workers()
            worker_script = get(RUNNER_WORKER_SCRIPT_PATHS, w, sp)
            remotecall_fetch(w, worker_script) do path
                Base.invokelatest(_drive_worker_include!, path)
            end
        end
        print_ok("✓")
        writeln_both("")
    catch
        print_progress_err("✗")
        writeln_both("")
        rethrow()
    end
end

"""
    run_prepare_workers!()

Optional hook: if the driver defines `prepare_workers!()`, call it on every
process after [`sync_driver_to_workers!`](@ref). Use this for worker-local setup
that cannot be expressed as `@everywhere` inside `main()` (e.g. extra `using` of
packages that are not the host application's main module).
"""
function run_prepare_workers!()
    isdefined(Main, :prepare_workers!) || return
    write_both("  Running prepare_workers!... ")
    flush(stdout)
    try
        @eval @everywhere Base.invokelatest(Main.prepare_workers!)
        print_ok("✓")
        writeln_both("")
    catch e
        print_progress_err("✗ ($(sprint(showerror, e)))")
        writeln_both("")
        rethrow()
    end
end

function init_drive_workers!(proj_dir::String, explicit_package, path_anchor::String)
    write_both("Initializing workers... ")
    flush(stdout)
    try
        worker_ids = workers()
        responses = Int[]
        failed_workers = Int[]

        _ping_retries = something(tryparse(Int, get(ENV, "DISTRIBUTED_PING_RETRIES", "6")), 6)
        for w in worker_ids
            local r_ok
            r_ok = nothing
            local last_ex
            last_ex = nothing
            for attempt in 1:max(1, _ping_retries)
                try
                    r_ok = remotecall_fetch(() -> myid(), w)
                    break
                catch e
                    last_ex = e
                    attempt < max(1, _ping_retries) && sleep(0.4 * attempt)
                end
            end
            if r_ok !== nothing
                push!(responses, r_ok)
            else
                push!(failed_workers, w)
                @warn "Worker $w not responding" exception=something(last_ex, ErrorException("unknown"))
            end
        end

        if !isempty(failed_workers)
            writeln_both("($(length(failed_workers)) workers failed to respond)")
            for w in failed_workers
                try
                    rmprocs(w)
                catch
                end
            end
        end

        isempty(responses) && error("No workers responding")

        print_ok("✓ ($(length(responses)) workers)")
        writeln_both("")
        write_both("  Loading packages on workers... ")
        flush(stdout)

        @eval @everywhere ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
        @eval @everywhere using Pkg
        # Master already has these from this file; `@everywhere` without
        # `workers()` would warn-overwrite pid 1 on every drive.
        @eval @everywhere workers() begin
            function _drive_worker_activate!(path::String)
                Pkg.activate(path; io=devnull)
                return nothing
            end
            function _drive_worker_include!(path::String)
                Base.include(Main, path)
                return nothing
            end
        end
        for w in workers()
            worker_proj = get(RUNNER_WORKER_PROJECT_DIRS, w, proj_dir)
            remotecall_fetch(w, worker_proj) do path
                Base.invokelatest(_drive_worker_activate!, path)
            end
        end

        pkg_name = explicit_package !== nothing ? explicit_package : project_package_name(proj_dir)
        if pkg_name !== nothing
            pkg_sym = Symbol(pkg_name)
            try
                host_workers = Dict{String, Int}()
                for w in workers()
                    host = remotecall_fetch(() -> gethostname(), w)
                    if !haskey(host_workers, host)
                        host_workers[host] = w
                    end
                end

                precompile_futures = [remotecall(w) do
                    Pkg.precompile(; io=devnull)
                end for (_, w) in host_workers]
                for f in precompile_futures
                    fetch(f)
                end

                # Skip processes where the binding already exists (e.g. master
                # already loaded DistSSHKit via `julia -m DistSSHKit`).
                @eval @everywhere begin
                    if !isdefined(Main, $(QuoteNode(pkg_sym)))
                        using $pkg_sym
                    end
                end

                for w in workers()
                    remotecall_fetch(() -> true, w)
                end

                print_ok("✓ ($pkg_name loaded)")
                writeln_both("")
            catch e
                print_progress_err("✗")
                writeln_both("")
                writeln_both("ERROR: failed to load package $(pkg_name): $(sprint(showerror, e))")
                rethrow()
            end
        elseif !isfile(joinpath(proj_dir, "Project.toml"))
            writeln_both("(no Project.toml in $(display_path(proj_dir, path_anchor)))")
        else
            writeln_both("(no package name in Project.toml; use --package NAME)")
        end

        write_both("  Verifying workers... ")
        flush(stdout)
        test_results = pmap(_ -> (myid(), 1 + 1), workers())
        working_count = count(r -> r[2] == 2, test_results)
        print_ok("✓ ($working_count workers verified)")
        writeln_both("")

        write_both("  Starting heartbeat monitors... ")
        flush(stdout)
        hb = DistSSHKit._heartbeat_config()
        hb_src = read(joinpath(@__DIR__, "heartbeat.jl"), String)
        @eval @everywhere begin
            include_string(@__MODULE__, $(hb_src))
            const HEARTBEAT_STOP = Ref(false)

            function stop_heartbeat_monitor()
                HEARTBEAT_STOP[] = true
            end

            function start_heartbeat_monitor()
                myid() == 1 && return
                _run_heartbeat!(HEARTBEAT_STOP, $(hb.interval), $(hb.deadline))
                return nothing
            end
        end
        @everywhere start_heartbeat_monitor()

        for w in workers()
            remotecall_fetch(() -> (flush(stdout); flush(stderr); true), w)
        end
        print_ok("✓")
        writeln_both("")
    catch e
        print_progress_err("✗")
        writeln_both("")
        @warn "Worker initialization failed" exception=e
        rethrow()
    end
    writeln_both("")
end
