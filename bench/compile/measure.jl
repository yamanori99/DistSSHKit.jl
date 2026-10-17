#!/usr/bin/env julia
# Precompile, load, and CLI compile time. Stdlib only.
#
#   julia --startup-file=no --project=. bench/compile/measure.jl --out result.toml [--slot 1.13]
#
# `--phase` is an internal child mode. Do not pass it.

using Dates
using Pkg
using TOML

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const TRACE_RX = r"^#=\s*([0-9.]+)\s*ms\s*=#\s*precompile\((.*)\)\s*(# recompile)?\s*$"

function julia_bin()::String
    return joinpath(Sys.BINDIR, Base.julia_exename())
end

function arg_value(flag::String)::String
    i = findfirst(==(flag), ARGS)
    i === nothing && error("missing $flag")
    i < length(ARGS) || error("missing value for $flag")
    return ARGS[i + 1]
end

function optional_arg(flag::String)::Union{Nothing, String}
    i = findfirst(==(flag), ARGS)
    i === nothing && return nothing
    i < length(ARGS) || error("missing value for $flag")
    return ARGS[i + 1]
end

function git_head()::String
    cmd = ignorestatus(`git -C $ROOT rev-parse HEAD`)
    out = IOBuffer()
    p = run(pipeline(cmd; stdout = out, stderr = devnull))
    p.exitcode == 0 || return ""
    return strip(String(take!(out)))
end

function cpu_model()::String
    if Sys.islinux() && isfile("/proc/cpuinfo")
        for line in eachline("/proc/cpuinfo")
            startswith(line, "model name") || continue
            return strip(split(line, ':'; limit = 2)[2])
        end
    elseif Sys.isapple()
        out = IOBuffer()
        p = run(pipeline(ignorestatus(`sysctl -n machdep.cpu.brand_string`); stdout = out, stderr = devnull))
        p.exitcode == 0 && return strip(String(take!(out)))
    end
    return string(Sys.ARCH)
end

function julia_commit()::String
    info = Base.GIT_VERSION_INFO
    if hasproperty(info, :commit_short) && !isempty(String(info.commit_short))
        return String(info.commit_short)
    end
    c = String(info.commit)
    return isempty(c) ? "" : c[1:min(10, end)]
end

function owner_name(sig::AbstractString)::String
    if occursin("typeof(Core.kwcall)", sig)
        matches = collect(eachmatch(r"typeof\(([A-Za-z_][A-Za-z0-9_]*)\.", sig))
        return isempty(matches) ? "other" : only(matches[end].captures)
    end
    m = match(r"typeof\(([A-Za-z_][A-Za-z0-9_]*)\.", sig)
    return m === nothing ? "other" : only(m.captures)
end

function bucket_name(name::String)::String
    name in ("DistSSHBase", "DistSSHUp") && return "DistSSHRun"
    name in ("DistSSHKit", "DistSSHQueue", "DistSSHRun") && return name
    name in ("Base", "Core") && return "Base"
    return "stdlib"
end

function parse_trace(path::AbstractString)::Vector{NamedTuple{(:ms, :bucket, :signature, :recompile), Tuple{Float64, String, String, Bool}}}
    rows = NamedTuple{(:ms, :bucket, :signature, :recompile), Tuple{Float64, String, String, Bool}}[]
    isfile(path) || return rows
    for line in eachline(path)
        m = match(TRACE_RX, line)
        m === nothing && continue
        sig = m.captures[2]
        push!(
            rows, (
                ms = parse(Float64, m.captures[1]),
                bucket = bucket_name(owner_name(sig)),
                signature = sig,
                recompile = m.captures[3] !== nothing,
            )
        )
    end
    return rows
end

function trace_summary(path::AbstractString, package::String)::Dict{String, Any}
    rows = parse_trace(path)
    totals = Dict{String, Float64}()
    counts = Dict{String, Int}()
    main_ms = 0.0
    needle = "typeof($package.main)"
    for row in rows
        totals[row.bucket] = get(totals, row.bucket, 0.0) + row.ms
        counts[row.bucket] = get(counts, row.bucket, 0) + 1
        occursin(needle, row.signature) && (main_ms += row.ms)
    end
    buckets = Dict{String, Any}()
    for name in ("DistSSHKit", "DistSSHQueue", "DistSSHRun", "Base", "stdlib")
        buckets[name] = Dict{String, Any}(
            "count" => get(counts, name, 0),
            "ms" => get(totals, name, 0.0),
        )
    end
    ranked = sort(rows; by = row -> row.ms, rev = true)
    top = Dict{String, Any}[]
    for row in ranked[1:min(20, end)]
        push!(
            top, Dict{String, Any}(
                "ms" => row.ms,
                "bucket" => row.bucket,
                "signature" => row.signature,
                "recompile" => row.recompile,
            )
        )
    end
    return Dict{String, Any}(
        "count" => length(rows),
        "total_ms" => sum(row -> row.ms, rows; init = 0.0),
        "main_ms" => main_ms,
        "buckets" => buckets,
        "top" => top,
    )
end

function child_env(depot::AbstractString, extra::AbstractDict)::Dict{String, String}
    env = Dict{String, String}(string(k) => string(v) for (k, v) in ENV)
    env["JULIA_DEPOT_PATH"] = depot
    env["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
    for (k, v) in extra
        env[string(k)] = string(v)
    end
    return env
end

function capture(cmd::Cmd)::Tuple{Int, String, Float64}
    out = IOBuffer()
    t0 = time()
    p = run(pipeline(cmd; stdout = out, stderr = devnull))
    return (p.exitcode, String(take!(out)), time() - t0)
end

function phase_precompile()
    package = arg_value("--package")
    spec = Base.identify_package(package)
    spec === nothing && error("identify_package failed for $package")
    println("FULL_BEGIN")
    flush(stdout)
    full = @elapsed Pkg.precompile(; io = devnull)
    println("FULL_SEC ", full)
    flush(stdout)
    depot = DEPOT_PATH[1]
    compiled = joinpath(depot, "compiled")
    if isdir(compiled)
        for ver in readdir(compiled)
            cache = joinpath(compiled, ver, package)
            isdir(cache) || continue
            rm(cache; force = true, recursive = true)
        end
    end
    println("PKG_BEGIN")
    flush(stdout)
    alone = @elapsed Base.compilecache(spec)
    println("PKG_SEC ", alone)
    flush(stdout)
    return nothing
end

function parse_seconds(text::AbstractString, key::String)::Float64
    for line in split(text, '\n')
        startswith(line, key * " ") || continue
        return parse(Float64, split(line)[2])
    end
    error("missing $key in child output")
end

function measure_precompile(depot::AbstractString, package::String)::Dict{String, Any}
    env = child_env(depot, Dict{String, String}())
    inst = setenv(`$(julia_bin()) --startup-file=no --project=$ROOT -e 'using Pkg; Pkg.instantiate()'`, env)
    code, _, _ = capture(ignorestatus(inst))
    code == 0 || error("instantiate failed: $code")
    cmd = setenv(
        `$(julia_bin()) --startup-file=no --project=$ROOT $(@__FILE__) --phase precompile --package $package`,
        env,
    )
    code, text, _ = capture(ignorestatus(cmd))
    code == 0 || error("precompile phase failed: $code\n$text")
    return Dict{String, Any}(
        "full_sec" => parse_seconds(text, "FULL_SEC"),
        "pkg_sec" => parse_seconds(text, "PKG_SEC"),
    )
end

function measure_using(depot::AbstractString, package::String)::Dict{String, Any}
    env = child_env(depot, Dict{String, String}())
    code = """
    t = @elapsed @eval(using $package)
    println("USING_SEC ", t)
    """
    cmd = setenv(`$(julia_bin()) --startup-file=no --project=$ROOT -e $code`, env)
    status, text, _ = capture(ignorestatus(cmd))
    status == 0 || error("using failed: $status\n$text")
    imports_code = """
    using InteractiveUtils
    @time_imports using $package
    """
    icmd = setenv(`$(julia_bin()) --startup-file=no --project=$ROOT -e $imports_code`, env)
    status, itext, _ = capture(ignorestatus(icmd))
    status == 0 || error("time_imports failed: $status\n$itext")
    imports = Dict{String, Any}[]
    plain = replace(itext, r"\e\[[0-9;]*m" => "")
    for line in split(plain, '\n')
        m = match(r"^\s*([0-9.]+)\s+ms\s+(DistSSH\w+)\s*$", line)
        m === nothing && continue
        push!(imports, Dict{String, Any}("name" => m.captures[2], "ms" => parse(Float64, m.captures[1])))
    end
    return Dict{String, Any}(
        "using_sec" => parse_seconds(text, "USING_SEC"),
        "imports" => imports,
    )
end

function command_env(raw::Any, store::AbstractString)::Dict{String, String}
    env = Dict{String, String}()
    raw isa AbstractDict || return env
    for (k, v) in raw
        env[string(k)] = replace(string(v), "{store}" => store)
    end
    return env
end

function median(xs::Vector{Float64})::Float64
    ys = sort(xs)
    return ys[(length(ys) + 1) ÷ 2]
end

function measure_command(
        depot::AbstractString,
        package::String,
        spec::AbstractDict,
        store::AbstractString,
    )::Dict{String, Any}
    name = string(spec["name"])
    args = String[string(a) for a in spec["args"]]
    extra = command_env(get(spec, "env", nothing), store)
    env = child_env(depot, extra)
    jl = julia_bin()
    walls = Float64[]
    trace = joinpath(mktempdir(), "trace.jl")
    traced = setenv(
        `$(jl) --startup-file=no --project=$ROOT --trace-compile=$trace --trace-compile-timing -m $package $args`,
        env,
    )
    code, _, wall = capture(ignorestatus(traced))
    push!(walls, wall)
    for _ in 1:2
        cmd = setenv(`$(jl) --startup-file=no --project=$ROOT -m $package $args`, env)
        status, _, w = capture(ignorestatus(cmd))
        status != 0 && (code = status)
        push!(walls, w)
    end
    summary = trace_summary(trace, package)
    summary["name"] = name
    summary["args"] = args
    summary["exit"] = code
    summary["wall_sec"] = median(walls)
    summary["walls_sec"] = walls
    return summary
end

function source_stats(root::AbstractString)::Dict{String, Any}
    # `src/**/*.jl` only. `src_lines` counts physical lines. `src_code_lines`
    # drops blank lines, so a time jump can be compared with a size jump.
    files = 0
    lines = 0
    code_lines = 0
    bytes = 0
    src = joinpath(root, "src")
    if isdir(src)
        for (dir, _, names) in walkdir(src)
            for name in names
                endswith(name, ".jl") || continue
                text = read(joinpath(dir, name), String)
                files += 1
                bytes += sizeof(text)
                parts = split(text, '\n')
                if !isempty(parts) && isempty(parts[end])
                    pop!(parts)
                end
                lines += length(parts)
                code_lines += count(line -> !isempty(strip(line)), parts)
            end
        end
    end
    return Dict{String, Any}(
        "src_files" => files,
        "src_lines" => lines,
        "src_code_lines" => code_lines,
        "src_bytes" => bytes,
    )
end

function package_version(root::AbstractString)::String
    proj = TOML.parsefile(joinpath(root, "Project.toml"))
    return string(get(proj, "version", ""))
end

function measure()
    out = arg_value("--out")
    slot = optional_arg("--slot")
    commands = TOML.parsefile(joinpath(@__DIR__, "commands.toml"))
    package = string(commands["package"])
    depot = mktempdir()
    store = joinpath(mktempdir(), "jobs.toml")
    # An empty file is bad TOML and `status` exits 1. An empty job list is the quiet path.
    write(store, "jobs = []\n")
    stats = source_stats(ROOT)
    pre = measure_precompile(depot, package)
    load = measure_using(depot, package)
    specs = commands["command"]
    specs isa AbstractDict && (specs = [specs])
    rows = Dict{String, Any}[]
    for spec in specs
        row = measure_command(depot, package, spec, store)
        row["exit"] == 0 || error("command $(row["name"]) failed: $(row["exit"])")
        push!(rows, row)
    end
    result = Dict{String, Any}(
        "repo" => package,
        "version" => package_version(ROOT),
        "commit" => git_head(),
        "time" => Dates.format(now(UTC), "yyyy-mm-ddTHH:MM:SS") * "Z",
        "julia" => string(VERSION),
        "julia_commit" => julia_commit(),
        "cpu" => cpu_model(),
        "threads" => Sys.CPU_THREADS,
        "os" => string(Sys.KERNEL),
        "slot" => something(slot, "local"),
        "src_files" => stats["src_files"],
        "src_lines" => stats["src_lines"],
        "src_code_lines" => stats["src_code_lines"],
        "src_bytes" => stats["src_bytes"],
        "precompile_full_sec" => pre["full_sec"],
        "precompile_pkg_sec" => pre["pkg_sec"],
        "using_sec" => load["using_sec"],
        "imports" => load["imports"],
        "commands" => rows,
    )
    open(out, "w") do io
        TOML.print(io, result)
    end
    println(stderr, "wrote ", out)
    return nothing
end

function main()
    if any(==("--phase"), ARGS) && optional_arg("--phase") == "precompile"
        phase_precompile()
    else
        measure()
    end
    return nothing
end

main()
