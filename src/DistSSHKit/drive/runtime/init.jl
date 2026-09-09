using Pkg

function _drive_eval_main(w, ex)
    # `Core.eval` on the wire — not a DistSSHKit closure / `@spawnat` thunk.
    return remotecall_fetch(Core.eval, Int(w), Main, ex)
end

function _drive_include_main(w, src::String)
    return remotecall_fetch(Base.include_string, Int(w), Main, src)
end

function _drive_eval_workers(ex)
    for w in workers()
        _drive_eval_main(w, ex)
    end
    return nothing
end

function _drive_include_workers(src::String)
    for w in workers()
        _drive_include_main(w, src)
    end
    return nothing
end

function _drive_invokelatest_main(w, name::Symbol, args...)
    return _drive_eval_main(
        w,
        Expr(:call, GlobalRef(Base, :invokelatest), GlobalRef(Main, name), args...),
    )
end

# Source text (not a DistSSHKit-quoted `function` Expr) so workers define
# these names in Main without serializing kit gensyms.
const _DRIVE_WORKER_BOOTSTRAP = """
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
using Pkg
function _drive_worker_activate!(path::String)
    Pkg.activate(path; io = devnull)
    return nothing
end
function _drive_worker_include!(path::String)
    Base.include(Main, path)
    return nothing
end
function _drive_worker_publish!(src::String, path::String)
    isempty(src) && return nothing
    tls = task_local_storage()
    prev = get(tls, :SOURCE_PATH, nothing)
    tls[:SOURCE_PATH] = path
    try
        include_string(Main, src, path)
    finally
        if prev === nothing
            delete!(tls, :SOURCE_PATH)
        else
            tls[:SOURCE_PATH] = prev
        end
    end
    return nothing
end
nothing
"""

"""
    activate_drive_project!(proj_dir)

Activate the host application project on the master process before the driver
script is first `include`d. Workers are activated separately during init.
"""
function activate_drive_project!(proj_dir::String)
    isdir(proj_dir) || return
    isfile(joinpath(proj_dir, "Project.toml")) || return
    Pkg.activate(proj_dir; io = devnull)
    return
end

"""
    sync_driver_to_workers!(script_path; sync_script=false)

Publish driver code onto workers after the project package has been loaded.
Default: definitions / `using` / `import` / `include` (not top-level work).
`sync_script=true` re-`include`s the full file (opt-in side effects on every
process). Definitions on the master are compiled in the post-package-load
world (Julia 1.12+ world age).

`init_output_dir!` is invoked separately on the master before workers start.
"""
function sync_driver_to_workers!(script_path::String; sync_script::Bool = false)
    sp = abspath(String(script_path))
    write_both("  Syncing driver to workers... ")
    flush(stdout)
    return try
        DistSSHKit._with_progress_job_stdio_capture!() do
            if sync_script
                for w in workers()
                    worker_script = get(RUNNER_WORKER_SCRIPT_PATHS, w, sp)
                    _drive_invokelatest_main(w, :_drive_worker_include!, worker_script)
                end
            else
                src = DistSSHKit._drive_publish_source(sp)
                if !isempty(src)
                    for w in workers()
                        worker_script = get(RUNNER_WORKER_SCRIPT_PATHS, w, sp)
                        _drive_invokelatest_main(w, :_drive_worker_publish!, src, worker_script)
                    end
                end
            end
            for w in workers()
                _drive_eval_main(w, :(flush(stdout); flush(stderr); true))
            end
            yield()
            sleep(0.05)
            yield()
            return nothing
        end
        print_ok("✓")
        writeln_both("")
        DistSSHKit._print_job_stdout_if_detail!()
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
    return try
        Base.invokelatest(Main.prepare_workers!)
        _drive_eval_workers(:(Base.invokelatest(Main.prepare_workers!)))
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
                    r_ok = _drive_eval_main(w, :(myid()))
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
                @warn "Worker $w not responding" exception = something(last_ex, ErrorException("unknown"))
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

        _drive_include_workers(_DRIVE_WORKER_BOOTSTRAP)
        mapped = Set{Int}()
        for (host, ids) in DistSSHKit.DRIVE_HOST_WORKER_IDS
            DistSSHKit._drive_host_span!(host, "init", :running)
            try
                for w in ids
                    w in workers() || continue
                    push!(mapped, Int(w))
                    worker_proj = get(RUNNER_WORKER_PROJECT_DIRS, w, proj_dir)
                    _drive_invokelatest_main(w, :_drive_worker_activate!, worker_proj)
                end
                DistSSHKit._drive_host_span!(host, "init", :ok)
            catch
                DistSSHKit._drive_host_span!(host, "init", :fail)
                rethrow()
            end
        end
        for w in workers()
            Int(w) in mapped && continue
            worker_proj = get(RUNNER_WORKER_PROJECT_DIRS, w, proj_dir)
            _drive_invokelatest_main(w, :_drive_worker_activate!, worker_proj)
        end

        pkg_name = explicit_package !== nothing ? explicit_package : project_package_name(proj_dir)
        if pkg_name !== nothing
            pkg_sym = Symbol(pkg_name)
            try
                host_workers = Dict{String, Int}()
                for w in workers()
                    host = _drive_eval_main(w, :(gethostname()))
                    if !haskey(host_workers, host)
                        host_workers[host] = w
                    end
                end

                @sync for (_, w) in host_workers
                    @async _drive_eval_main(w, :(Pkg.precompile(; io = devnull)))
                end

                # Skip processes where the binding already exists (e.g. master
                # already loaded DistSSHKit via `julia -m DistSSHKit`).
                load_src = """
                if !isdefined(Main, $(repr(pkg_sym)))
                    using $pkg_sym
                end
                """
                _drive_include_workers(load_src)

                for w in workers()
                    _drive_eval_main(w, :(true))
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
        ws = workers()
        test_results = Vector{Any}(undef, length(ws))
        @sync for (i, w) in enumerate(ws)
            @async test_results[i] = _drive_eval_main(w, :((myid(), 1 + 1)))
        end
        working_count = count(r -> r[2] == 2, test_results)
        print_ok("✓ ($working_count workers verified)")
        writeln_both("")

        write_both("  Starting heartbeat monitors... ")
        flush(stdout)
        hb = _heartbeat_config()
        hb_src = read(joinpath(@__DIR__, "heartbeat.jl"), String)
        hb_boot = """
        include_string(Main, $(repr(hb_src)))
        const HEARTBEAT_STOP = Ref(false)
        function stop_heartbeat_monitor()
            HEARTBEAT_STOP[] = true
        end
        function start_heartbeat_monitor()
            myid() == 1 && return
            _run_heartbeat!(HEARTBEAT_STOP, $(hb.interval), $(hb.deadline))
            return nothing
        end
        """
        include_string(Main, hb_boot)
        for w in workers()
            _drive_include_main(w, hb_boot)
        end
        _drive_eval_workers(:(start_heartbeat_monitor()))

        for w in workers()
            _drive_eval_main(w, :(flush(stdout); flush(stderr); true))
        end
        print_ok("✓")
        writeln_both("")
    catch e
        print_progress_err("✗")
        writeln_both("")
        @warn "Worker initialization failed" exception = e
        rethrow()
    end
    return writeln_both("")
end
