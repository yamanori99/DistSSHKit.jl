# `plan` — inspect a script; do not start a job.

const _PLAN_DRIVE_CALLS = (
    :pmap,
    :worker_pmap,
    :remotecall,
    :remotecall_fetch,
    :remotecall_wait,
    :remote_do,
    :workers,
    :nworkers,
    :addprocs,
    :rmprocs,
)

const _PLAN_DRIVE_MACROS = (
    Symbol("@distributed"),
    Symbol("@everywhere"),
    Symbol("@spawn"),
    Symbol("@spawnat"),
    Symbol("@fetch"),
    Symbol("@fetchfrom"),
)

"""One syntax finding from [`plan`](@ref)."""
struct PlanFinding
    line::Int
    kind::Symbol
    status::Symbol
    excerpt::String
end

"""Result of [`plan`](@ref). Does not start a job."""
struct KitPlan
    script::String
    suggest::Symbol
    findings::Vector{PlanFinding}
    julia::String
    ok::Bool
    error::Union{Nothing,String}
    slots::Union{Nothing,WorkerPlan}
end

function _plan_call_name(f)::Union{Nothing,Symbol}
    f isa Symbol && return f
    f isa GlobalRef && return f.name
    if f isa Expr && f.head === :. && length(f.args) == 2
        q = f.args[2]
        q isa QuoteNode && q.value isa Symbol && return q.value
    end
    return nothing
end

function _plan_excerpt(ex; max::Int=72)::String
    s = replace(sprint(show, ex), r"\s+" => " ")
    n = ncodeunits(s)
    n <= max && return s
    i = prevind(s, max)
    return s[1:i] * "…"
end

function _plan_push!(
    acc::Vector{PlanFinding},
    line::Int,
    kind::Symbol,
    status::Symbol,
    ex,
)
    push!(acc, PlanFinding(line, kind, status, _plan_excerpt(ex)))
    return nothing
end

function _plan_expr_mentions_symbol(ex, name::Symbol)::Bool
    ex === name && return true
    ex isa Expr || return false
    for a in ex.args
        a isa LineNumberNode && continue
        _plan_expr_mentions_symbol(a, name) && return true
    end
    return false
end

function _plan_expr_has_escape(ex)::Bool
    ex isa Expr || return false
    h = ex.head
    h in (:break, :continue, :return) && return true
    for a in ex.args
        _plan_expr_has_escape(a) && return true
    end
    return false
end

function _plan_for_body_stmts(body)::Vector{Any}
    body isa Expr && body.head === :block || return Any[body]
    stmts = Any[]
    for a in body.args
        a isa LineNumberNode && continue
        a isa Expr && a.head === :linenumber && continue
        push!(stmts, a)
    end
    return stmts
end

"""
Indexed fill `for i in iter; dest[i] = rhs; end` with no `dest` in `rhs`.
Workers can compute `rhs`; the parent writes `dest` afterward.
"""
function _plan_index_fill_for(ex::Expr)
    ex.head === :for || return nothing
    length(ex.args) == 2 || return nothing
    it, body = ex.args
    it isa Expr && it.head === :(=) && length(it.args) == 2 || return nothing
    var = it.args[1]
    var isa Symbol || return nothing
    iter = it.args[2]
    stmts = _plan_for_body_stmts(body)
    length(stmts) == 1 || return nothing
    asg = stmts[1]
    asg isa Expr && asg.head === :(=) && length(asg.args) == 2 || return nothing
    lhs, rhs = asg.args
    lhs isa Expr && lhs.head === :ref && length(lhs.args) == 2 || return nothing
    dest = lhs.args[1]
    dest isa Symbol || return nothing
    lhs.args[2] === var || return nothing
    _plan_expr_mentions_symbol(rhs, dest) && return nothing
    _plan_expr_has_escape(rhs) && return nothing
    return (var=var, iter=iter, dest=dest, rhs=rhs)
end

function _plan_walk!(acc::Vector{PlanFinding}, ex, line::Int)::Int
    if ex isa LineNumberNode
        return ex.line
    elseif !(ex isa Expr)
        return line
    end
    h = ex.head
    args = ex.args
    if h === :linenumber && !isempty(args) && args[1] isa Integer
        return Int(args[1])
    end
    if h === :macrocall && !isempty(args)
        m = args[1]
        m isa GlobalRef && (m = m.name)
        if m isa Symbol && m in _PLAN_DRIVE_MACROS
            ln = line
            length(args) >= 2 && args[2] isa LineNumberNode && (ln = args[2].line)
            _plan_push!(acc, ln, :distributed, :drive_vocab, ex)
        end
    elseif h === :call && !isempty(args)
        name = _plan_call_name(args[1])
        if name in _PLAN_DRIVE_CALLS
            _plan_push!(acc, line, :distributed, :drive_vocab, ex)
        elseif name === :map
            _plan_push!(acc, line, :map, :candidate, ex)
        elseif name === :filter
            _plan_push!(acc, line, :filter, :candidate, ex)
        end
    elseif h === :comprehension || h === :typed_comprehension
        _plan_push!(acc, line, :comprehension, :candidate, ex)
    elseif h === :for
        if _plan_index_fill_for(ex) !== nothing
            _plan_push!(acc, line, :for, :candidate, ex)
        else
            _plan_push!(acc, line, :for, :out_of_scope, ex)
        end
    end
    for a in args
        line = _plan_walk!(acc, a, line)
    end
    return line
end

function _plan_suggest(findings::Vector{PlanFinding})::Symbol
    any(f -> f.status === :drive_vocab, findings) && return :drive
    any(f -> f.status === :candidate, findings) && return :ride
    return :go
end

"""
    plan(script; session=nothing, workers=[], project=pwd(),
         gb_per_worker=nothing, probe=nothing, mem_headroom, parent_gb) -> KitPlan

Inspect `script` without starting a job. Syntax only: Distributed vocabulary,
`map` / `filter` / comprehensions, and independent indexed `for`
(`dest[i] = …`). Accumulating or multi-statement `for` is out of scope.
Effect analysis is not applied at this stage.

Suggests `:drive`, `:ride`, or `:go`. The caller still chooses the command.

Slot estimates (`slots::WorkerPlan`) run only when `session` is given, or
when `workers` / `gb_per_worker` / `probe` request sizing. That path calls
[`size!`](@ref) internally. Default is syntax only (no SSH probe).
"""
function plan(
    script::AbstractString;
    session::Union{Nothing,KitSession}=nothing,
    workers::AbstractVector{<:AbstractString}=String[],
    project::AbstractString=pwd(),
    gb_per_worker::Union{Nothing,Real}=nothing,
    probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    parent_gb::Real=DEFAULT_PARENT_GB,
)::KitPlan
    path = String(script)
    julia = string(VERSION)
    empty = KitPlan(
        path, :go, PlanFinding[], julia, false, "file not found: $path", nothing,
    )
    isfile(path) || return empty
    src = read(path, String)
    expr = try
        Meta.parseall(src; filename=path)
    catch e
        return KitPlan(
            path, :go, PlanFinding[], julia, false, sprint(showerror, e), nothing,
        )
    end
    findings = PlanFinding[]
    _plan_walk!(findings, expr, 1)
    suggest = _plan_suggest(findings)
    want_size = session !== nothing || !isempty(workers) ||
        gb_per_worker !== nothing || probe !== nothing
    slots = nothing
    err = nothing
    ok = true
    if want_size
        sess = if session !== nothing
            session
        else
            KitSession(;
                project=project,
                workers=workers,
                yes=true,
                quiet=true,
            )
        end
        try
            slots = size!(
                sess;
                gb_per_worker=gb_per_worker,
                probe=probe,
                mem_headroom=mem_headroom,
                parent_gb=parent_gb,
            )
        catch e
            ok = false
            err = sprint(showerror, e)
        end
    end
    return KitPlan(path, suggest, findings, julia, ok, err, slots)
end

function _plan_status_label(st::Symbol)::String
    st === :candidate && return "distributable (syntax)"
    st === :out_of_scope && return "out of scope (rewrite as map)"
    st === :drive_vocab && return "Distributed vocabulary"
    return String(st)
end

"""Print a [`KitPlan`](@ref) (CLI and tests)."""
function print_plan(kp::KitPlan; io::IO=stdout)
    println(io, "Planning ", kp.script, "...")
    println(io)
    if !kp.ok
        println(io, "  error: ", something(kp.error, "unknown"))
        return nothing
    end
    if isempty(kp.findings)
        println(io, "  (no map / filter / comprehension / for / Distributed calls)")
        println(io)
    else
        for f in kp.findings
            loc = "$(basename(kp.script)):$(f.line)"
            println(io, "  ", rpad(loc, 28), " ", rpad(String(f.kind), 14), " ",
                _plan_status_label(f.status))
        end
        println(io)
    end
    cmd = String(kp.suggest)
    println(io, "  suggest:  ", cmd, " ", kp.script)
    if kp.slots !== nothing
        toks = resolved_placement_tokens(kp.slots)
        if isempty(toks)
            println(io, "  slots:    (none)")
        else
            println(io, "  slots:    ", join(toks, " "))
        end
    end
    println(io, "  julia:    ", kp.julia, " / syntax")
    kp.suggest === :ride && println(io,
        "  note:     effect_free is not proven here; ride decides at run time")
    kp.suggest === :go && any(f -> f.status === :out_of_scope, kp.findings) &&
        println(io, "  note:     rewrite independent loops as map or a comprehension")
    return nothing
end

function _drive_is_short_method(ex::Expr)::Bool
    ex.head === :(=) || return false
    lhs = ex.args[1]
    lhs isa Expr || return false
    h = lhs.head
    h === :call && return true
    h === :where && return true
    return h === :(::) && lhs.args[1] isa Expr && lhs.args[1].head === :call
end

function _drive_is_include_call(ex::Expr)::Bool
    ex.head === :call && !isempty(ex.args) || return false
    return _plan_call_name(ex.args[1]) === :include
end

function _drive_keep_publish(ex)::Bool
    ex isa Expr || return false
    h = ex.head
    h in (:function, :macro, :struct, :abstract, :primitive, :using, :import, :module, :const) &&
        return true
    _drive_is_short_method(ex) && return true
    return _drive_is_include_call(ex)
end

function _drive_collect_publish!(pieces::Vector{Any}, ex)
    ex isa Expr || return
    h = ex.head
    if h === :block || h === :toplevel
        for a in ex.args
            a isa LineNumberNode && continue
            _drive_collect_publish!(pieces, a)
        end
        return
    end
    _drive_keep_publish(ex) && push!(pieces, ex)
    return
end

"""Worker source: defs / `using` / `import` / `include`, not top-level work."""
function _drive_publish_source(script_path::AbstractString)::String
    path = String(script_path)
    src = read(path, String)
    expr = Meta.parseall(src; filename=path)
    pieces = Any[]
    _drive_collect_publish!(pieces, expr)
    isempty(pieces) && return ""
    return sprint(print, Expr(:block, pieces...))
end

function _drive_plain_script_hint(
    kp::KitPlan;
    shown::AbstractString=kp.script,
)::String
    cmd = String(kp.suggest)
    shown_s = String(shown)
    return string(
        "drive: no Distributed vocabulary in this file (plan suggests $cmd)\n",
        "  $shown_s\n\n",
        "  Load is this include (once). Publish sends defs / using / include to workers.\n",
        "  Run is main() if defined; otherwise Load is the run. plan scans this file only.\n",
        "  Full-file worker include: --sync-script. Rewrite or independent slots:\n\n",
        "    julia --project=. -m DistSSHKit $cmd $shown_s",
    )
end

"""`nothing` if this file has Distributed vocabulary; otherwise a warning body."""
function _drive_plain_script_hint(
    script_path::AbstractString,
    project::AbstractString;
    shown::AbstractString=script_path,
)::Union{Nothing,String}
    kp = plan(script_path; project=project)
    kp.ok || return nothing
    any(f -> f.status === :drive_vocab, kp.findings) && return nothing
    return _drive_plain_script_hint(kp; shown=shown)
end
