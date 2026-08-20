# Result types for the drive / sync API.

"""Default RAM fraction usable for workers in [`size!`](@ref) / `size`."""
const DEFAULT_MEM_HEADROOM = 0.75
"""Default GB reserved for the master process on localhost sizing."""
const DEFAULT_MASTER_GB = 0.4
"""Drive preflight: same fraction as [`DEFAULT_MEM_HEADROOM`](@ref)."""
const MEMORY_CAPACITY_FRACTION = DEFAULT_MEM_HEADROOM
"""Multiplier applied to measured RSS when estimating per-worker GB."""
const WORKER_RSS_SAFETY_FACTOR = 1.1
"""Floor for estimated per-worker GB after RSS measurement."""
const WORKER_MEMORY_GB_FLOOR = 0.5
"""Fallback per-worker GB when RSS is unavailable (drive preflight)."""
const WORKER_MEMORY_GB_FALLBACK = 1.5

"""
Convert RSS bytes to a per-worker GB estimate (safety factor + floor).
"""
function rss_bytes_to_worker_gb(rss_bytes::Integer)::Float64
    rss_bytes > 0 || return WORKER_MEMORY_GB_FALLBACK
    gb = rss_bytes / 1024^3 * WORKER_RSS_SAFETY_FACTOR
    return round(max(gb, WORKER_MEMORY_GB_FLOOR), digits=2)
end

"""
    size_worker_count(total_gb, nproc, per_worker_gb; mem_headroom, master_gb, is_localhost)

Pure RAM/CPU cap for one host (shared by CLI and `compute_worker_plan`).
"""
function size_worker_count(
    total_gb::Real,
    nproc::Integer,
    per_worker_gb::Real;
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
    is_localhost::Bool=false,
)::Int
    pw = Float64(per_worker_gb)
    pw <= 0 && return 0
    avail = Float64(total_gb) * Float64(mem_headroom) - (is_localhost ? Float64(master_gb) : 0.0)
    cpu_reserve = is_localhost ? 2 : 1
    return min(
        max(0, floor(Int, avail / pw)),
        max(1, Int(nproc) - cpu_reserve),
    )
end

"""Per-host outcome for sync and similar operations."""
struct HostResult
    host::String
    ok::Bool
    message::String
end

"""Outcome of `sync!` (rsync or git sync). `cancelled` is set when a confirm prompt is aborted."""
struct SyncResult
    ok::Bool
    hosts::Vector{HostResult}
    cancelled::Bool
end

"""Sized worker counts per host (`local_workers` + `remote_workers`)."""
struct WorkerPlan
    local_workers::Int
    remote_workers::Dict{String,Int}
end

WorkerPlan() = WorkerPlan(0, Dict{String,Int}())

"""
Parsed drive/go worker tokens (counts may still need [`size!`](@ref)).

Build with [`parse_worker_tokens`](@ref); the keyword constructor here only
coerces types (same convenience shape as [`DriveResult`](@ref) /
[`PipelineResult`](@ref)), it does not re-validate cross-field consistency.

Field name matches [`WorkerPlan`](@ref): a host with an explicit `:N` is
`remote_workers[host] = N`, same key as `WorkerPlan.remote_workers`.
"""
struct ParsedWorkerTokens
    local_workers::Int
    local_autosize::Bool
    remote_workers::Dict{String,Int}
    remote_auto::Vector{String}
    remote_hosts::Vector{String}
    tokens::Vector{String}
end

function ParsedWorkerTokens(;
    local_workers::Integer=0,
    local_autosize::Bool=false,
    remote_workers::AbstractDict{<:AbstractString,<:Integer}=Dict{String,Int}(),
    remote_auto::AbstractVector{<:AbstractString}=String[],
    remote_hosts::AbstractVector{<:AbstractString}=String[],
    tokens::AbstractVector{<:AbstractString}=String[],
)
    return ParsedWorkerTokens(
        Int(local_workers),
        local_autosize,
        Dict{String,Int}(String(h) => Int(n) for (h, n) in remote_workers),
        String[String(h) for h in remote_auto],
        String[String(h) for h in remote_hosts],
        String[String(t) for t in tokens],
    )
end

"""
    parse_worker_tokens(tokens) -> ParsedWorkerTokens

Classify CLI-style tokens. Explicit `:N` is fixed; bare hosts are sized later.
`local` / `l` / `localhost` are local; everything else is remote SSH.
"""
function parse_worker_tokens(
    tokens::AbstractVector{<:AbstractString},
)::ParsedWorkerTokens
    local_workers = 0
    local_seen = false
    local_autosize = false
    remote_workers = Dict{String,Int}()
    remote_auto = String[]
    remote_hosts = String[]
    seen_remote = Set{String}()
    out_tokens = String[String(t) for t in tokens]

    for raw in out_tokens
        host, n = split_worker_token(raw)
        if is_local_host_name(host)
            local_seen && throw(ArgumentError(
                "duplicate local worker token; use one of l:N, local:N, or localhost:N",
            ))
            local_seen = true
            if n === nothing
                local_autosize = true
            else
                local_workers = Int(n)
            end
        else
            if !(host in seen_remote)
                push!(remote_hosts, host)
                push!(seen_remote, host)
            end
            if n === nothing
                push!(remote_auto, host)
            else
                remote_workers[host] = Int(n)
            end
        end
    end
    return ParsedWorkerTokens(
        local_workers,
        local_autosize,
        remote_workers,
        remote_auto,
        remote_hosts,
        out_tokens,
    )
end

"""True when every token has an explicit worker/slot count (`:N`)."""
function worker_tokens_fully_specified(parsed::ParsedWorkerTokens)::Bool
    return !parsed.local_autosize && isempty(parsed.remote_auto)
end

"""SSH host names from tokens (local tokens omitted)."""
function remote_hosts_from_tokens(tokens::AbstractVector{<:AbstractString})::Vector{String}
    return parse_worker_tokens(tokens).remote_hosts
end

"""
Per-host RSS sample from `measure_rss`.

`baseline_gb` is after package load. `peak_gb` is after an optional warm-up
probe script (equals baseline when no probe runs). Suggestions use
`effective_worker_gb` = `max(baseline, peak)`.
"""
struct WorkerMemorySample
    baseline_gb::Float64
    peak_gb::Float64
end

"""GB used for worker-count math (`max` of baseline and peak)."""
effective_worker_gb(s::WorkerMemorySample)::Float64 = max(s.baseline_gb, s.peak_gb)

"""Map host → effective GB for `compute_worker_plan`."""
function per_worker_gb_dict(samples::Dict{String,WorkerMemorySample})::Dict{String,Float64}
    return Dict{String,Float64}(h => effective_worker_gb(s) for (h, s) in samples)
end

"""Optional path string (`nothing` when unset or empty)."""
function _optional_path(path::Union{Nothing,AbstractString})::Union{Nothing,String}
    path === nothing && return nothing
    s = String(path)
    return isempty(s) ? nothing : s
end

"""
Shared run outcome for the queue layer (`ok`, `kind`, dirs, `failed_step`, `exit_code`).

`kind` is `:go`, `:drive`, or `:pipeline`. Convert with [`kit_run_result`](@ref).
"""
struct KitRunResult
    ok::Bool
    kind::Symbol
    output_dir::Union{Nothing,String}
    log_dir::Union{Nothing,String}
    failed_step::Union{Nothing,String}
    exit_code::Int
end

"""
Outcome of [`drive!`](@ref) (and similar CLI steps that return an exit code).

`output_dir` / `log_dir` are the directories actually used for this run —
resolved the same way `drive` reports `Results:` / writes its log, even when
`drive!` was not called with `output_dir=` / `log_dir=`. `nothing` when no
real run happened (e.g. built by hand) or, for `log_dir`, when logging was
disabled.
"""
struct DriveResult
    ok::Bool
    exit_code::Int
    output_dir::Union{Nothing,String}
    log_dir::Union{Nothing,String}
    failed_step::Union{Nothing,String}
end

function DriveResult(
    ok::Bool,
    exit_code::Int;
    output_dir::Union{Nothing,AbstractString}=nothing,
    log_dir::Union{Nothing,AbstractString}=nothing,
    failed_step::Union{Nothing,AbstractString}=nothing,
)
    return DriveResult(
        ok,
        exit_code,
        _optional_path(output_dir),
        _optional_path(log_dir),
        failed_step === nothing ? nothing : String(failed_step),
    )
end

"""Outcome of `collect!`."""
struct CollectResult
    ok::Bool
    exit_code::Int
end

"""
    PipelineConfig

Settings for [`pipeline!`](@ref): sync, worker tokens, driver run, and optional collect.

Worker placement uses CLI-style tokens (`local:2`, `user@host:1`). Bare hosts are
sized via [`size!`](@ref). Set `sync=false` to skip sync. Set `collect=false`
to skip rsync-back. Git parity is off by default; pass `skip_hash_check=false`
(or CLI `--require-git`) to require matching remote commits.

`julia` sets the remote Julia binary (`nothing` / `"auto"` → detect; same as
CLI `--julia`). Prefer [`pipeline!(driver, workers...; …)`](@ref pipeline!) for
day-to-day use.
"""
mutable struct PipelineConfig
    project::String
    tokens::Vector{String}
    remote::Union{Nothing,String}
    hosts_file::Union{Nothing,String}
    quiet::Bool
    verbosity::Union{Nothing,Symbol}
    yes::Bool
    driver::String
    args::Vector{String}
    sync::Union{Symbol,Bool,Nothing}
    gb_per_worker::Union{Nothing,Float64}
    size_probe::Union{Nothing,String}
    mem_headroom::Float64
    master_gb::Float64
    skip_hash_check::Union{Nothing,Bool}
    collect_spec::Union{Symbol,Bool,AbstractString,Nothing}
    collect_merge::Bool
    output_dir::Union{Nothing,String}
    enable_log::Bool
    log_dir::Union{Nothing,String}
    package::Union{Nothing,String}
    julia::Union{Nothing,String}
end

function PipelineConfig(;
    project::AbstractString=pwd(),
    workers::AbstractVector{<:AbstractString}=String[],
    remote::Union{Nothing,AbstractString}=nothing,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=true,
    driver::AbstractString,
    args::AbstractVector{<:AbstractString}=String[],
    sync::Union{Symbol,Bool,Nothing}=nothing,
    gb_per_worker::Union{Nothing,Real}=nothing,
    size_probe::Union{Nothing,AbstractString}=nothing,
    mem_headroom::Real=DEFAULT_MEM_HEADROOM,
    master_gb::Real=DEFAULT_MASTER_GB,
    skip_hash_check::Union{Nothing,Bool}=nothing,
    collect::Union{Symbol,Bool,AbstractString,Nothing}=nothing,
    collect_merge::Bool=false,
    output_dir::Union{Nothing,AbstractString}=nothing,
    enable_log::Bool=true,
    log_dir::Union{Nothing,AbstractString}=nothing,
    package::Union{Nothing,AbstractString}=nothing,
    julia::Union{Nothing,AbstractString}=nothing,
)
    rr = remote === nothing ? nothing : String(strip(String(remote)))
    rr !== nothing && isempty(rr) && (rr = nothing)
    hf = hosts_file === nothing ? nothing : String(strip(String(hosts_file)))
    hf !== nothing && isempty(hf) && (hf = nothing)
    gbp = gb_per_worker === nothing ? nothing : Float64(gb_per_worker)
    probe = size_probe === nothing ? nothing : String(size_probe)
    probe !== nothing && isempty(strip(probe)) && (probe = nothing)
    od = output_dir === nothing ? nothing : String(output_dir)
    ld = log_dir === nothing ? nothing : String(log_dir)
    pkg = package === nothing ? nothing : String(package)
    jl = if julia === nothing || isempty(strip(String(julia))) ||
            lowercase(strip(String(julia))) == "auto"
        nothing
    else
        String(julia)
    end
    return PipelineConfig(
        canonical_local_path(project),
        String[String(t) for t in workers],
        rr,
        hf,
        quiet,
        verbosity,
        yes,
        String(driver),
        Base.collect(String, args),
        sync,
        gbp,
        probe,
        Float64(mem_headroom),
        Float64(master_gb),
        skip_hash_check,
        collect,
        collect_merge,
        od,
        enable_log,
        ld,
        pkg,
        jl,
    )
end

"""Combined outcome of [`pipeline!`](@ref). On failure, `failed_step` names the step that stopped."""
struct PipelineResult
    ok::Bool
    sync::Union{Nothing,SyncResult}
    plan::Union{Nothing,WorkerPlan}
    drive::Union{Nothing,DriveResult}
    collect::Union{Nothing,CollectResult}
    driver::String
    failed_step::Union{Nothing,String}
    output_dir::Union{Nothing,String}
    log_dir::Union{Nothing,String}
    exit_code::Int
end

function _result_exit_code(
    ok::Bool,
    drive::Union{Nothing,DriveResult},
    collect::Union{Nothing,CollectResult},
    failed_step::Union{Nothing,AbstractString}=nothing,
)::Int
    ok && return 0
    step = failed_step === nothing ? nothing : String(failed_step)
    if step in ("run", "drive") && drive !== nothing
        return drive.exit_code
    end
    if step == "collect" && collect !== nothing
        return collect.exit_code
    end
    collect !== nothing && !collect.ok && return collect.exit_code
    drive !== nothing && !drive.ok && return drive.exit_code
    return 1
end

function PipelineResult(
    ok::Bool,
    sync::Union{Nothing,SyncResult},
    plan::Union{Nothing,WorkerPlan},
    drive::Union{Nothing,DriveResult},
    collect::Union{Nothing,CollectResult},
    driver::String;
    failed_step::Union{Nothing,String}=nothing,
    output_dir::Union{Nothing,AbstractString}=nothing,
    log_dir::Union{Nothing,AbstractString}=nothing,
    exit_code::Union{Nothing,Integer}=nothing,
)
    od = _optional_path(output_dir)
    ld = _optional_path(log_dir)
    if drive !== nothing
        od === nothing && (od = drive.output_dir)
        ld === nothing && (ld = drive.log_dir)
    end
    code = exit_code === nothing ? _result_exit_code(ok, drive, collect, failed_step) : Int(exit_code)
    return PipelineResult(ok, sync, plan, drive, collect, driver, failed_step, od, ld, code)
end

"""Build [`KitRunResult`](@ref) from a kit outcome (`:go` / `:drive` / `:pipeline`)."""
function kit_run_result(result::DriveResult)::KitRunResult
    return KitRunResult(
        result.ok,
        :drive,
        result.output_dir,
        result.log_dir,
        result.failed_step,
        result.exit_code,
    )
end

function kit_run_result(result::PipelineResult)::KitRunResult
    return KitRunResult(
        result.ok,
        :pipeline,
        result.output_dir,
        result.log_dir,
        result.failed_step,
        result.exit_code,
    )
end

function _report_run_label(kind::Symbol)::String
    return kind === :pipeline ? "pipeline!" : String(kind)
end

function _report_run_header!(io::IO, result::KitRunResult)
    step = something(result.failed_step, "unknown")
    println(io, "$(_report_run_label(result.kind)) failed at step: $step")
    if result.output_dir !== nothing
        println(io, "  output: $(result.output_dir)")
    end
    if result.log_dir !== nothing
        println(io, "  log: $(result.log_dir)")
    end
    return nothing
end

function _report_sync_host_errors!(io::IO, sync::Union{Nothing,SyncResult})
    sync === nothing && return
    sync.ok && return
    for hr in sync.hosts
        !hr.ok && println(io, "  sync $(hr.host): $(hr.message)")
    end
    return nothing
end

"""
    report_run_errors(result; io=stderr)

Print a short summary when a kit run failed. Accepts [`KitRunResult`](@ref)
or a typed outcome (`GoResult` / `DriveResult` / `PipelineResult`).
Returns `result.ok`.
"""
function report_run_errors(result::KitRunResult; io::IO=stderr)::Bool
    result.ok && return true
    _report_run_header!(io, result)
    if result.exit_code != 0
        println(io, "  exit $(result.exit_code)")
    end
    return false
end

function report_run_errors(result::DriveResult; io::IO=stderr)::Bool
    return report_run_errors(kit_run_result(result); io=io)
end

"""Build `drive` host specs from a [`WorkerPlan`](@ref)."""
function drive_host_specs(plan::WorkerPlan)::Vector{String}
    specs = String[]
    if plan.local_workers > 0
        push!(specs, "local:$(plan.local_workers)")
    end
    for (host, n) in plan.remote_workers
        n > 0 && push!(specs, "$(host):$n")
    end
    return specs
end

function SyncResult(
    cancelled::Bool,
    host_results::Vector{HostResult};
    ok::Union{Nothing,Bool}=nothing,
)
    if ok === nothing
        ok = !cancelled && all(hr.ok for hr in host_results)
    end
    return SyncResult(ok, host_results, cancelled)
end
