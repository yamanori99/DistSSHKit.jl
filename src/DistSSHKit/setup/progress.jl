# Shared Time / sidecar for CLI `setup` and `setup!`. Host rows are
# `step/host` items (same nesting as drive `host/leaf`). No-op when a go/drive
# progress run is already active (`sync!` from drive must not steal the bar).

function setup_progress_step_name(mode::Symbol)::String
    mode === :rsync_push && return "rsync"
    mode === :rsync && return "rsync"
    return String(mode)
end

function _setup_host_outcome_ok(r)::Bool
    r isa Bool && return r
    hasproperty(r, :ok) && return Bool(getfield(r, :ok))
    return true
end

"""Log `current-step/host` when the live run is `kind=:setup`."""
function _setup_host_span!(host::AbstractString, status::Symbol)
    raw = KIT_PROGRESS[]
    raw isa KitProgressState && raw.kind === :setup || return nothing
    step = raw.label
    isempty(step) && (step = raw.title)
    _kit_progress_span!(string(step, "/", host), status)
    return nothing
end

function _setup_host_call!(f, host::AbstractString)
    _setup_host_span!(host, :running)
    try
        r = f()
        _setup_host_span!(host, _setup_host_outcome_ok(r) ? :ok : :fail)
        return r
    catch
        _setup_host_span!(host, :fail)
        rethrow()
    end
end

"""
Run `f()` as one setup mode: sidecar, begin/step/done, Time table.

If `KIT_PROGRESS` is already set (nested `setup!`, or drive/go), just `f()`.
Opens the kit log when none is open (API path); CLI already opened it.
"""
function with_kit_setup_progress(
    f,
    log_dir::AbstractString,
    step::AbstractString;
    path_anchor::Union{Nothing,AbstractString}=nothing,
)
    KIT_PROGRESS[] isa KitProgressState && return f()
    dir = String(log_dir)
    opened_log = LOG_FILE_HANDLE[] === nothing
    if opened_log
        init_log_file(
            dir;
            prefix="setup",
            path_anchor=path_anchor === nothing ? nothing : String(path_anchor),
        )
    end
    _set_kit_progress_sidecar!(dir)
    kit_progress_begin!("setup"; steps=1, kind=:setup)
    kit_progress_step!(String(step))
    ok_ref = Ref(true)
    threw = false
    try
        r = f()
        if r isa Integer
            ok_ref[] = Int(r) == 0
        elseif hasproperty(r, :ok)
            cancelled = hasproperty(r, :cancelled) && Bool(getfield(r, :cancelled))
            ok_ref[] = Bool(getfield(r, :ok)) && !cancelled
        end
        return r
    catch
        ok_ref[] = false
        threw = true
        rethrow()
    finally
        kit_progress_done!(; ok=ok_ref[])
        threw || _maybe_print_kit_progress_phases(dir)
        _set_kit_progress_sidecar!(nothing)
        opened_log && close_log_file()
    end
end
