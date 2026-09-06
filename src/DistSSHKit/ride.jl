# `ride` — rewrite map / filter / comprehension and run (experimental).
# Workers: parent `addprocs`, or SSH children via drive `add_drive_workers!`.

const _RIDE_DEPTH = Ref(0)
const _RIDE_SPI = Ref(true)
const _RIDE_SPI_OK = Ref{Union{Nothing,Bool}}(nothing)

"""Outcome of [`ride!`](@ref). Experimental."""
struct RideResult
    ok::Bool
    script::String
    workers::Int
    spi_ok::Union{Nothing,Bool}
    error::Union{Nothing,String}
    julia::String
    output_dir::Union{Nothing,String}
end

RideResult(
    ok::Bool,
    script::AbstractString,
    workers::Integer,
    spi_ok::Union{Nothing,Bool},
    error::Union{Nothing,String},
    julia::AbstractString,
) = RideResult(ok, String(script), Int(workers), spi_ok, error, String(julia), nothing)

function kit_run_result(
    result::RideResult,
    tokens::AbstractVector{<:AbstractString}=String[],
)::KitRunResult
    return KitRunResult(
        result.ok,
        :ride,
        result.output_dir,
        nothing,
        result.ok ? nothing : "ride",
        result.ok ? 0 : 1,
        HostRunResult[],
        tokens,
    )
end

function _ride_reset_runtime!(; spi_check::Bool)
    _RIDE_DEPTH[] = 0
    _RIDE_SPI[] = spi_check
    _RIDE_SPI_OK[] = nothing
    return nothing
end

function _ride_effects_free(f, T)::Bool
    try
        e = Base.infer_effects(f, Tuple{T})
        return Core.Compiler.is_effect_free(e)
    catch
        return false
    end
end

function _ride_index_free(xs)::Bool
    try
        e = Base.infer_effects(Base.getindex, Tuple{typeof(xs),Int})
        return Core.Compiler.is_effect_free(e)
    catch
        return false
    end
end

function _ride_apply_named(name::Symbol, x)
    f = getglobal(Main, name)
    return Base.invokelatest(f, x)
end

function _ride_callable(f)
    f isa Symbol && return (x -> _ride_apply_named(f, x))
    return f
end

function _ride_named_fn(name::Symbol, value)
    isdefined(Main, name) && getglobal(Main, name) === value && return name
    return value
end

function _can_distribute(f, xs)::Bool
    isempty(xs) && return false
    nprocs() < 2 && return false
    T = eltype(xs)
    fn = try
        f isa Symbol ? getglobal(Main, f) : f
    catch
        return false
    end
    return _ride_effects_free(fn, T) && _ride_index_free(xs)
end

function _ride_compare(a, b)::Bool
    try
        return a == b
    catch
        return false
    end
end

"""Runtime `map` used after [`ride!`](@ref) rewrite. Sequential if unsafe or nested."""
function _ride_map(f, xs)
    _RIDE_DEPTH[] += 1
    try
        _RIDE_DEPTH[] > 1 && return map(_ride_callable(f), xs)
        if !_can_distribute(f, xs)
            return map(_ride_callable(f), xs)
        end
        dist = pmap(_ride_callable(f), xs)
        if _RIDE_SPI[]
            seq = map(_ride_callable(f), xs)
            ok = _ride_compare(dist, seq)
            _RIDE_SPI_OK[] = something(_RIDE_SPI_OK[], true) && ok
            ok || error("ride: SPI check failed on map (worker count changed the result)")
        end
        return dist
    finally
        _RIDE_DEPTH[] -= 1
    end
end

"""Runtime `filter` used after [`ride!`](@ref) rewrite."""
function _ride_filter(f, xs)
    _RIDE_DEPTH[] += 1
    try
        _RIDE_DEPTH[] > 1 && return filter(_ride_callable(f), xs)
        if !_can_distribute(f, xs)
            return filter(_ride_callable(f), xs)
        end
        flags = pmap(_ride_callable(f), xs)
        dist = xs[findall(identity, flags)]
        if _RIDE_SPI[]
            seq = filter(_ride_callable(f), xs)
            ok = _ride_compare(dist, seq)
            _RIDE_SPI_OK[] = something(_RIDE_SPI_OK[], true) && ok
            ok || error("ride: SPI check failed on filter (worker count changed the result)")
        end
        return dist
    finally
        _RIDE_DEPTH[] -= 1
    end
end

function _ride_map_fn_arg(fex)
    fex isa Symbol && return Expr(
        :call,
        GlobalRef(DistSSHKit, :_ride_named_fn),
        QuoteNode(fex),
        fex,
    )
    return _ride_rewrite(fex)
end

function _ride_rewrite(ex)
    ex isa LineNumberNode && return ex
    ex isa Expr || return ex
    h = ex.head
    args = ex.args
    if h === :call && !isempty(args)
        name = _plan_call_name(args[1])
        if name === :map && length(args) == 3
            fex = _ride_map_fn_arg(args[2])
            rest = Any[_ride_rewrite(a) for a in args[3:end]]
            return Expr(
                :call,
                GlobalRef(DistSSHKit, :_ride_map),
                fex,
                rest...,
            )
        elseif name === :filter && length(args) == 3
            fex = _ride_map_fn_arg(args[2])
            rest = Any[_ride_rewrite(a) for a in args[3:end]]
            return Expr(
                :call,
                GlobalRef(DistSSHKit, :_ride_filter),
                fex,
                rest...,
            )
        end
    elseif h === :comprehension && length(args) == 1
        gen = args[1]
        if gen isa Expr && gen.head === :generator && length(gen.args) == 2
            body, it = gen.args
            if it isa Expr && it.head === :(=) && length(it.args) == 2
                var, iter = it.args
                return Expr(
                    :call,
                    GlobalRef(DistSSHKit, :_ride_map),
                    Expr(:->, var, _ride_rewrite(body)),
                    _ride_rewrite(iter),
                )
            end
        end
    end
    return Expr(h, Any[_ride_rewrite(a) for a in args]...)
end

function _ride_drive_vocab_error(kp::KitPlan)::String
    hit = findfirst(f -> f.status === :drive_vocab, kp.findings)
    loc = hit === nothing ? kp.script : "$(kp.script):$(kp.findings[hit].line)"
    excerpt = hit === nothing ? "Distributed vocabulary" : kp.findings[hit].excerpt
    return string(
        "ride: script uses Distributed vocabulary at $loc\n",
        "  $excerpt\n\n",
        "  ride expects a plain script; it distributes automatically.\n",
        "  For explicit distribution, use drive instead:\n\n",
        "    julia --project=. -m DistSSHKit drive $(kp.script) ...",
    )
end

function _ride_collect_prelude!(pieces::Vector{Any}, ex)
    ex isa Expr || return
    h = ex.head
    if h === :block || h === :toplevel
        for a in ex.args
            a isa LineNumberNode && continue
            _ride_collect_prelude!(pieces, a)
        end
        return
    elseif h in (:function, :macro, :struct, :abstract, :primitive, :using, :import, :module)
        push!(pieces, ex)
    elseif h === :const
        push!(pieces, ex)
    end
    return
end

"""Top-level defs to eval on workers so named `map(f, …)` can `pmap`."""
function _ride_worker_prelude(ex)::Expr
    pieces = Any[]
    _ride_collect_prelude!(pieces, ex)
    return Expr(:block, pieces...)
end

function _ride_eval_on_worker(src::String)
    include_string(Main, src)
    return nothing
end

function _ride_load_self_on_workers!()
    pkg = Base.PkgId(DistSSHKit)
    for w in workers()
        remotecall_fetch(Base.require, w, pkg)
    end
    return nothing
end

function _ride_push_prelude!(ex)
    prelude = _ride_worker_prelude(ex)
    isempty(prelude.args) && return
    src = sprint(print, prelude)
    for w in workers()
        remotecall_fetch(_ride_eval_on_worker, w, src)
    end
    return nothing
end

function _ride_resolve_plan(
    tokens::Vector{String};
    session::Union{Nothing,KitSession},
    gb_per_worker,
    probe,
    mem_headroom,
    parent_gb,
)::WorkerPlan
    isempty(tokens) && return WorkerPlan(1, Dict{String,Int}())
    return worker_plan_from_tokens(
        tokens;
        session=session,
        gb_per_worker=gb_per_worker,
        probe=probe,
        mem_headroom=mem_headroom,
        parent_gb=parent_gb,
    )
end

function _ride_init_drive_workers!(proj_dir::AbstractString)
    isdefined(Main, :init_drive_workers!) || return
    init = getfield(Main, :init_drive_workers!)
    anchor = if isdefined(Main, :_PATH_ANCHOR)
        String(getfield(Main, :_PATH_ANCHOR))
    else
        String(proj_dir)
    end
    init(String(proj_dir), nothing, anchor)
    return nothing
end

function _ride_add_workers!(
    plan::WorkerPlan,
    project::AbstractString,
    script_path::AbstractString,
    julia,
    require_all_hosts::Bool,
)::Vector{Int}
    before = Set(workers())
    try
        child_hosts = Tuple{String,Union{Int,Nothing}}[
            (String(h), Int(n)) for (h, n) in plan.child_workers if n > 0
        ]
        if isempty(child_hosts)
            n = plan.parent_workers
            n > 0 && addprocs(
                n;
                topology=:master_worker,
                exeflags=_drive_worker_exeflags(project),
            )
        else
            _ensure_drive_fragments!(project)
            isdefined(Main, :add_drive_workers!) || error("ride: drive runtime not loaded")
            julia_exe = if julia === nothing || strip(String(julia)) == "" ||
                    lowercase(strip(String(julia))) == "auto"
                nothing
            else
                String(julia)
            end
            addw = getfield(Main, :add_drive_workers!)
            successful = addw(
                child_hosts,
                plan.parent_workers,
                1,
                julia_exe,
                String(project),
                String(script_path),
            )
            if require_all_hosts
                wanted = String[h for (h, _) in child_hosts]
                missing = String[h for h in wanted if !(h in successful)]
                isempty(missing) || error(
                    "ride: required hosts did not join: $(join(missing, ", "))",
                )
                if plan.parent_workers > 0
                    got = _drive_parent_worker_count()
                    got >= plan.parent_workers || error(
                        "ride: required parent workers did not join: wanted $(plan.parent_workers), got $got",
                    )
                end
            end
            if isdefined(Main, :wait_for_worker_connections!)
                getfield(Main, :wait_for_worker_connections!)(; ssh=!isempty(child_hosts))
            end
            _ride_init_drive_workers!(project)
        end
        added = Int[w for w in workers() if w ∉ before]
        isempty(added) || _ride_load_self_on_workers!()
        return added
    catch
        leftover = Int[w for w in workers() if w ∉ before]
        isempty(leftover) || rmprocs(leftover; waitfor=30)
        rethrow()
    end
end

"""
    ride!(script, workers...; args=[], spi_check=true, output_dir=nothing, project=pwd())

Experimental. Rewrite `map` / `filter` / simple comprehensions and run the
script on Distributed workers (parent and optional SSH `child:`). Rejects
Distributed vocabulary (use [`drive!`](@ref)).

Worker add for SSH children is the same `add_drive_workers!` path as drive.
The script still runs on the parent (no driver `include` on workers). Named
functions used by `map` / `filter` are sent to workers as a prelude.

`--spi-check` (default on) compares the distributed result to a sequential
`map` / `filter`. Unknown syntax stays sequential. Inspect first with
[`plan`](@ref). Listed `child:` hosts are fail-closed (`require_all_hosts=true`).
Queue: [`execute!`](@ref) `:ride` (`detached=true` writes `kit.result` like go).
"""
function ride!(
    script::AbstractString,
    tokens::AbstractString...;
    kwargs...,
)
    return ride!(script, String[String(t) for t in tokens]; kwargs...)
end

function _ride_batch_dir(
    script::AbstractString,
    output_dir::Union{Nothing,AbstractString};
    project::AbstractString=pwd(),
)::String
    if output_dir !== nothing
        return canonical_local_path(String(output_dir))
    end
    return allocate_output_dir(:ride, script; project=project)
end

function _ride_run_script!(rewritten)
    kit_output_progress() || begin
        Base.invokelatest(Core.eval, Main, rewritten)
        return nothing
    end
    orig_stdout = stdout
    rd, wr = redirect_stdout()
    reader = @async begin
        try
            while true
                data = readavailable(rd)
                isempty(data) || _append_job_stdout_capture!(data)
                isempty(data) && (eof(rd) || !isopen(wr)) && break
            end
        catch e
            isa(e, Base.IOError) || rethrow()
        end
    end
    try
        Base.invokelatest(Core.eval, Main, rewritten)
    finally
        flush(stdout)
        close(wr)
        wait_ok = @async wait(reader)
        for _ in 1:4
            istaskdone(wait_ok) && break
            sleep(0.05)
        end
        if !istaskdone(wait_ok)
            close(rd)
            wait(reader)
        end
        redirect_stdout(orig_stdout)
    end
    return nothing
end

function _ride_print_spi_progress!(spi::Union{Nothing,Bool})
    kit_output_progress() || return nothing
    msg = if spi === nothing
        "skipped (sequential or off)"
    else
        spi ? "passed" : "failed"
    end
    println_fatal("  SPI check: $msg")
    return nothing
end

function ride!(
    script::AbstractString,
    tokens::AbstractVector{<:AbstractString};
    args::AbstractVector{<:AbstractString}=String[],
    spi_check::Bool=true,
    output_dir::Union{Nothing,AbstractString}=nothing,
    project::AbstractString=pwd(),
    julia::Union{Nothing,AbstractString}=nothing,
    remote::Union{Nothing,AbstractString}=nothing,
    session::Union{Nothing,KitSession}=nothing,
    gb_per_worker::Union{Nothing,Real}=nothing,
    probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    parent_gb::Real=DEFAULT_PARENT_GB,
    require_all_hosts::Bool=true,
)::RideResult
    path = canonical_local_path(script)
    julia_s = string(VERSION)
    kp = plan(path; project=project)
    !kp.ok && return RideResult(false, path, 0, nothing, something(kp.error, "plan failed"), julia_s)
    any(f -> f.status === :drive_vocab, kp.findings) &&
        return RideResult(false, path, 0, nothing, _ride_drive_vocab_error(kp), julia_s)
    tok = String[String(t) for t in tokens]
    wp = try
        _ride_resolve_plan(
            tok;
            session=session,
            gb_per_worker=gb_per_worker,
            probe=probe,
            mem_headroom=mem_headroom,
            parent_gb=parent_gb,
        )
    catch e
        e isa ArgumentError && return RideResult(
            false, path, 0, nothing, sprint(showerror, e), julia_s,
        )
        rethrow()
    end
    src = read(path, String)
    expr = try
        Meta.parseall(src; filename=path)
    catch e
        return RideResult(false, path, 0, nothing, sprint(showerror, e), julia_s)
    end
    rewritten = _ride_rewrite(expr)
    _ride_reset_runtime!(; spi_check=spi_check)
    added = Int[]
    old_args = copy(ARGS)
    old_out = get(ENV, "DISTRIBUTED_OUTPUT_DIR", nothing)
    old_remote = get(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT", nothing)
    batch_dir = _ride_batch_dir(path, output_dir; project=project)
    release_lock = () -> nothing
    progress_started = false
    progress_ok = false
    outcome = RideResult(false, path, 0, nothing, "aborted", julia_s, batch_dir)
    try
        if output_dir !== nothing
            ENV["DISTRIBUTED_OUTPUT_DIR"] = canonical_local_path(String(output_dir))
            mkpath(ENV["DISTRIBUTED_OUTPUT_DIR"])
        end
        if remote !== nothing
            rr = strip(String(remote))
            !isempty(rr) && (ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"] = rr)
        elseif session !== nothing
            rrs = session.remote
            rrs isa AbstractString && (ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"] = String(rrs))
        end
        empty!(ARGS)
        append!(ARGS, String[String(a) for a in args])
        mkpath(batch_dir)
        job_raw = strip(get(ENV, "DISTSSHKIT_JOB_ID", ""))
        _write_kit_pid_file(
            getpid(),
            batch_dir,
            nothing;
            job_id=isempty(job_raw) ? nothing : job_raw,
        )
        release_lock = kit_output_dir_lock!(batch_dir)
        _set_kit_progress_sidecar!(batch_dir)
        kit_progress_begin!("ride"; steps=3, kind=:ride)
        progress_started = true
        kit_progress_step!("workers")
        added = _ride_add_workers!(wp, project, path, julia, require_all_hosts)
        kit_progress_step!("init")
        _ride_push_prelude!(expr)
        kit_progress_step!("run")
        _ride_run_script!(rewritten)
        progress_ok = true
        outcome = RideResult(true, path, length(added), _RIDE_SPI_OK[], nothing, julia_s, batch_dir)
        return outcome
    catch e
        outcome = RideResult(
            false, path, length(added), _RIDE_SPI_OK[], sprint(showerror, e), julia_s, batch_dir,
        )
        return outcome
    finally
        if progress_started
            footer = if progress_ok
                display_path(batch_dir, canonical_local_path(project))
            else
                nothing
            end
            kit_progress_done!(; ok=progress_ok, footer=footer)
            _print_job_stdout_after_progress!()
            progress_ok && _ride_print_spi_progress!(_RIDE_SPI_OK[])
            _maybe_print_kit_progress_phases(batch_dir)
            _set_kit_progress_sidecar!(nothing)
        end
        isdir(batch_dir) && _write_kit_result_file(kit_run_result(outcome))
        _remove_kit_pid_file(getpid(), batch_dir, nothing)
        release_lock()
        empty!(ARGS)
        append!(ARGS, old_args)
        if old_out === nothing
            delete!(ENV, "DISTRIBUTED_OUTPUT_DIR")
        else
            ENV["DISTRIBUTED_OUTPUT_DIR"] = old_out
        end
        if old_remote === nothing
            delete!(ENV, "DISTRIBUTED_REMOTE_PROJECT_ROOT")
        else
            ENV["DISTRIBUTED_REMOTE_PROJECT_ROOT"] = old_remote
        end
        !isempty(added) && rmprocs(added; waitfor=30)
        _RIDE_DEPTH[] = 0
    end
end

"""Print a [`RideResult`](@ref). Field names match go / drive (`Script:`, `Workers:`)."""
function print_ride(result::RideResult; io::IO=stdout)
    println(io, "DistSSHKit ride")
    println(io, "Script: ", result.script)
    println(io, "Workers: ", result.workers)
    println(io, "Julia: ", result.julia)
    result.output_dir !== nothing && println(io, "Output: ", result.output_dir)
    println(io, "DistSSHKit: ", dist_ssh_kit_version())
    spi = result.spi_ok
    if spi === nothing
        println(io, "SPI check: skipped (sequential or off)")
    else
        println(io, "SPI check: ", spi ? "passed" : "failed")
    end
    result.ok || println(io, "Error: ", something(result.error, "unknown"))
    return nothing
end

function report_run_errors(result::RideResult; io::IO=stderr)::Bool
    return report_run_errors(kit_run_result(result); io=io)
end
