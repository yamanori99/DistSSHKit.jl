# Per-run bundle (pid, logs, `run.toml`) separate from user artifact output.

const DISTSSHKIT_RUN_DIR_ENV::String = "DISTSSHKIT_RUN_DIR"
const _KIT_EXECUTE_KINDS = (:go, :drive, :ride)

function _require_execute_kind!(kind::Symbol)
    kind in _KIT_EXECUTE_KINDS || throw(
        ArgumentError(
            "execute! kind must be :go, :drive, or :ride, got $(repr(kind))",
        )
    )
    return nothing
end

"""`ENV["DISTSSHKIT_RUN_DIR"]` when set and non-blank, else `nothing`."""
function kit_run_dir()::Union{Nothing, String}
    raw = strip(get(ENV, DISTSSHKIT_RUN_DIR_ENV, ""))
    isempty(raw) && return nothing
    return canonical_local_path(raw)
end

"""Exclusive `mkdir` of `dir`. On EEXIST, retry `dir-<time_ns>`."""
function _mkdir_unique!(dir::AbstractString)::String
    mkpath(dirname(dir))
    base = String(dir)
    while true
        try
            mkdir(base)
            return canonical_local_path(base)
        catch e
            e isa Base.IOError || rethrow()
            e.code == Base.UV_EEXIST || rethrow()
            base = String(dir) * "-" * string(time_ns())
        end
    end
    return
end

"""
    allocate_run_dir(kind, script; project=pwd(), job_id=nothing) -> String

Create a unique Kit run directory (cancel / logs / `run.toml`), not the
artifact `output_dir`.

Layout: `{script dir}/.distsshkit/runs/<kind>/<script-stem>_<UTC-stamp>/`.
When `job_id` is set it is appended after the stamp (same charset as
[`execute!`](@ref) `job_id`).
"""
function allocate_run_dir(
        kind::Symbol,
        script::AbstractString;
        project::AbstractString = pwd(),
        job_id::Union{Nothing, AbstractString} = nothing,
    )::String
    _require_execute_kind!(kind)
    proj = canonical_local_path(project)
    isdir(proj) || throw(ArgumentError("allocate_run_dir: project is not a directory: $proj"))
    stem = splitext(basename(String(script)))[1]
    isempty(stem) && throw(ArgumentError("allocate_run_dir: empty script basename"))
    stamp = Dates.format(Dates.now(Dates.UTC), dateformat"yyyymmddTHHMMSS") * "Z"
    leaf = if job_id !== nothing && !isempty(strip(String(job_id)))
        "$(stem)_$(stamp)_$(_parse_kit_job_id(String(job_id)))"
    else
        "$(stem)_$(stamp)"
    end
    raw = String(script)
    script_path = isabspath(raw) ? raw : joinpath(proj, raw)
    script_dir = dirname(canonical_local_path(script_path))
    dir = joinpath(script_dir, ".distsshkit", "runs", String(kind), leaf)
    return _mkdir_unique!(dir)
end

function _ensure_kit_run_dir!(
        kind::Symbol,
        script::AbstractString;
        project::AbstractString = pwd(),
        job_id::Union{Nothing, AbstractString} = nothing,
    )::String
    existing = kit_run_dir()
    if existing !== nothing
        mkpath(existing)
        return existing
    end
    jid = job_id
    if jid === nothing
        jid = resolved_kit_job_id()
    end
    dir = allocate_run_dir(kind, script; project = project, job_id = jid)
    ENV[DISTSSHKIT_RUN_DIR_ENV] = dir
    return dir
end

function _restore_kit_run_dir_env!(old)::Nothing
    if old === nothing || (old isa AbstractString && isempty(strip(String(old))))
        delete!(ENV, DISTSSHKIT_RUN_DIR_ENV)
    else
        ENV[DISTSSHKIT_RUN_DIR_ENV] = String(old)
    end
    return nothing
end

"""Setup log directory: this run's `DISTSSHKIT_RUN_DIR`, else `{project}/.distsshkit/setup`."""
function setup_log_dir(project::AbstractString)::String
    rd = kit_run_dir()
    rd !== nothing && return rd
    return joinpath(canonical_local_path(project), ".distsshkit", "setup")
end

function kit_run_toml_path(run_dir::AbstractString)::String
    return joinpath(canonical_local_path(run_dir), "run.toml")
end

function _list_kit_run_logs(run_dir::AbstractString)::Vector{String}
    isdir(run_dir) || return String[]
    out = String[]
    for name in readdir(run_dir)
        endswith(lowercase(name), ".log") || continue
        push!(out, joinpath(run_dir, String(name)))
    end
    sort!(out)
    return out
end

function _collect_dirs_from_env()::Vector{String}
    spec = String(strip(get(ENV, "DISTRIBUTED_COLLECT_DIRS", "")))
    isempty(spec) && return String[]
    out = String[]
    seen = Set{String}()
    for chunk in split(spec, ':')
        p = String(strip(String(chunk)))
        isempty(p) && continue
        ap = canonical_local_path(expanduser(p))
        ap in seen && continue
        push!(seen, ap)
        push!(out, ap)
    end
    return out
end

"""Write machine-readable `run.toml` under `run_dir`. Never throws."""
function write_kit_run_toml!(
        run_dir::AbstractString;
        kind::Symbol,
        output_dir::Union{Nothing, AbstractString} = nothing,
        log_dir::Union{Nothing, AbstractString} = nothing,
        result::Union{Nothing, KitRunResult} = nothing,
    )
    d = canonical_local_path(run_dir)
    data = Dict{String, Any}(
        "schema" => 1,
        "kind" => String(kind),
        "run_dir" => d,
    )
    jid = resolved_kit_job_id()
    jid !== nothing && (data["job_id"] = jid)
    if output_dir !== nothing && !isempty(strip(String(output_dir)))
        data["output_dir"] = canonical_local_path(String(output_dir))
    end
    if log_dir !== nothing && !isempty(strip(String(log_dir)))
        data["log_dir"] = canonical_local_path(String(log_dir))
    end
    logs = _list_kit_run_logs(d)
    isempty(logs) || (data["logs"] = logs)
    cols = _collect_dirs_from_env()
    isempty(cols) || (data["collect_dirs"] = cols)
    if result !== nothing
        data["ok"] = result.ok
        data["exit_code"] = result.exit_code
        result.failed_step !== nothing && (data["failed_step"] = result.failed_step)
    end
    try
        mkpath(d)
        dest = kit_run_toml_path(d)
        tmp = dest * ".tmp"
        open(tmp, "w") do io
            TOML.print(io, data)
        end
        mv(tmp, dest; force = true)
    catch
        # best-effort only
    end
    return nothing
end

"""Read `run.toml` from a run directory (or the file itself). `nothing` if missing."""
function read_kit_run_toml(path::AbstractString)
    p = canonical_local_path(path)
    file = isdir(p) ? kit_run_toml_path(p) : p
    isfile(file) || return nothing
    raw = try
        TOML.parsefile(file)
    catch
        return nothing
    end
    return raw isa AbstractDict ? raw : nothing
end
