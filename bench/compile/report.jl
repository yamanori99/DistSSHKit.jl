#!/usr/bin/env julia
# Rebuild bench-data/README.md from history/<slot>/*.toml.
#
#   julia --startup-file=no bench/compile/report.jl \
#       --history /path/history --readme /path/README.md [--summary "$GITHUB_STEP_SUMMARY"]

using TOML

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

function load_history(dir::AbstractString)::Dict{String, Vector{Dict{String, Any}}}
    groups = Dict{String, Vector{Dict{String, Any}}}()
    isdir(dir) || return groups
    for (root, _, names) in walkdir(dir)
        for name in names
            endswith(name, ".toml") || continue
            data = TOML.parsefile(joinpath(root, name))
            slot = string(get(data, "slot", "local"))
            push!(get!(groups, slot, Dict{String, Any}[]), data)
        end
    end
    for rows in values(groups)
        sort!(rows; by = row -> string(get(row, "time", "")))
    end
    return groups
end

function fnum(x)::String
    x === nothing && return ""
    return string(round(Float64(x); digits = 2))
end

function inum(row, key)::String
    haskey(row, key) || return ""
    return string(Int(row[key]))
end

function command_wall(row, name::String)::Union{Nothing, Float64}
    for cmd in get(row, "commands", [])
        string(get(cmd, "name", "")) == name || continue
        return Float64(cmd["wall_sec"])
    end
    return nothing
end

function command_names(rows)::Vector{String}
    names = String[]
    for row in rows
        for cmd in get(row, "commands", [])
            name = string(get(cmd, "name", ""))
            name in names || push!(names, name)
        end
    end
    return names
end

function top_map(row, command::String)::Dict{String, Float64}
    found = Dict{String, Float64}()
    for cmd in get(row, "commands", [])
        string(get(cmd, "name", "")) == command || continue
        for item in get(cmd, "top", [])
            found[string(item["signature"])] = Float64(item["ms"])
        end
    end
    return found
end

function host_label(row)::String
    haskey(row, "os_name") || return ""
    os = string(row["os_name"])
    arch = string(get(row, "arch", ""))
    return strip(isempty(arch) ? os : os * " " * arch)
end

function flags_for(prev, cur)::Vector{String}
    out = String[]
    prev === nothing && return out
    prev_host = host_label(prev)
    cur_host = host_label(cur)
    if !isempty(prev_host) && !isempty(cur_host) && prev_host != cur_host
        push!(out, "host changed $prev_host -> $cur_host")
    end
    jprev = string(get(prev, "julia", ""))
    jcur = string(get(cur, "julia", ""))
    if !isempty(jprev) && !isempty(jcur) && jprev != jcur
        push!(out, "julia $jprev -> $jcur")
    end
    pkg_prev = Float64(prev["precompile_pkg_sec"])
    pkg_cur = Float64(cur["precompile_pkg_sec"])
    if pkg_cur >= pkg_prev * 1.5 && pkg_cur - pkg_prev >= 0.5
        push!(out, "package precompile $(fnum(pkg_prev))s -> $(fnum(pkg_cur))s")
    end
    for name in command_names([prev, cur])
        a = command_wall(prev, name)
        b = command_wall(cur, name)
        (a === nothing || b === nothing) && continue
        if b >= a * 1.5 && b - a >= 1.0
            push!(out, "$name wall $(fnum(a))s -> $(fnum(b))s")
        end
        before = top_map(prev, name)
        after = top_map(cur, name)
        for (sig, ms) in after
            ms < 200 && continue
            old = get(before, sig, nothing)
            grown = old === nothing || ms >= old * 2
            grown || continue
            short = length(sig) > 100 ? sig[1:100] * "..." : sig
            was = old === nothing ? "new" : fnum(old) * " ms"
            push!(out, "$name method $was -> $(fnum(ms)) ms: $short")
        end
    end
    return out
end

function chart_day(row)::String
    t = string(get(row, "time", ""))
    return length(t) >= 10 ? t[6:7] * "-" * t[9:10] : t
end

# OS family and arch. A Ubuntu point release is not a host switch.
function chart_host(row)::String
    haskey(row, "os_name") || return ""
    os = strip(string(row["os_name"]))
    isempty(os) && return ""
    word = first(split(os))
    arch = strip(string(get(row, "arch", "")))
    return isempty(arch) ? word : word * " " * arch
end

# `1.15.0-DEV` is the nightly Julia. The axis shows `1.15-DEV`.
function chart_julia(row)::String
    j = strip(string(get(row, "julia", "")))
    isempty(j) && return ""
    v = tryparse(VersionNumber, j)
    v === nothing && return j
    base = string(v.major, ".", v.minor)
    return isempty(v.prerelease) ? base : base * "-" * join(v.prerelease, ".")
end

function chart_label(slot::String, row, prev)::String
    day = chart_day(row)
    marks = String[]
    if prev === nothing && occursin("nightly", slot)
        julia = chart_julia(row)
        isempty(julia) || push!(marks, julia)
    elseif prev !== nothing
        ver = string(get(row, "version", ""))
        old = string(get(prev, "version", ""))
        if !isempty(ver) && ver != old
            push!(marks, "v" * ver)
        end
        julia = chart_julia(row)
        prev_julia = chart_julia(prev)
        if !isempty(julia) && !isempty(prev_julia) && julia != prev_julia
            push!(marks, "julia " * julia)
        end
        host = chart_host(row)
        prev_host = chart_host(prev)
        if !isempty(host) && !isempty(prev_host) && host != prev_host
            push!(marks, host)
        end
    end
    if !isempty(marks)
        return day * " " * join(marks, " ")
    end
    sha = string(get(row, "commit", ""))
    short = isempty(sha) ? "" : first(sha, 7)
    return isempty(short) ? day : day * " " * short
end

# Dark colors, one per command, in command order. The default #fff4dd line
# disappears on the white plot.
const CHART_COLORS = (
    "#1f4e79",
    "#b85c38",
    "#2d6a4f",
    "#6b4c9a",
    "#8a5a2b",
    "#1d6a78",
)

function chart_latest(names, rows)::Dict{String, Float64}
    latest = Dict{String, Float64}()
    for name in names
        for row in Iterators.reverse(rows)
            wall = command_wall(row, name)
            wall === nothing && continue
            latest[name] = wall
            break
        end
    end
    return latest
end

# One band, or a short band and a long band when the tallest latest value is
# more than four times the shortest. A short line otherwise sits on the axis.
function chart_bands(names, rows)::Vector{Vector{String}}
    latest = chart_latest(names, rows)
    present = [name for name in names if haskey(latest, name)]
    isempty(present) && return Vector{String}[]
    lo = minimum(latest[name] for name in present)
    hi = maximum(latest[name] for name in present)
    if lo > 0 && hi > 4 * lo
        short = [name for name in present if latest[name] <= 4 * lo]
        long = [name for name in present if latest[name] > 4 * lo]
        if !isempty(short) && !isempty(long)
            return [short, long]
        end
    end
    return [present]
end

function chart_ytoken(value::Union{Nothing, Float64})::String
    value === nothing && return "null"
    return string(round(value; digits = 2))
end

function chart(slot::String, names::Vector{String}, rows)::String
    isempty(names) && return ""
    labels = String[]
    series = Dict{String, Vector{Union{Nothing, Float64}}}(
        name => Union{Nothing, Float64}[] for name in names
    )
    prev = nothing
    for row in rows
        push!(labels, chart_label(slot, row, prev))
        for name in names
            push!(series[name], command_wall(row, name))
        end
        prev = row
    end
    plotted = [name for name in names if any(!isnothing, series[name])]
    isempty(plotted) && return ""
    # A one-point line is a zero-length path, so GitHub draws an empty plot.
    kind = length(labels) == 1 ? "bar" : "line"
    peak = 0.0
    for name in plotted
        for value in series[name]
            value === nothing && continue
            peak = max(peak, value)
        end
    end
    ymax = max(1, ceil(Int, peak * 1.2))
    xs = join((string('"', replace(x, '"' => "'"), '"') for x in labels), ", ")
    title = slot
    if occursin("nightly", slot)
        julia = chart_julia(prev)
        isempty(julia) || (title = "$slot $julia")
    end
    if length(chart_bands(command_names(rows), rows)) == 2
        title = title * " " * join(plotted, " ")
    end
    palette = join((CHART_COLORS[mod1(i, length(CHART_COLORS))] for i in eachindex(plotted)), ", ")
    lines = String[]
    for name in plotted
        ys = join((chart_ytoken(value) for value in series[name]), ", ")
        push!(lines, "        $kind \"$name\" [$ys]")
    end
    body = join(lines, "\n")
    # plotColorPalette replaces the default #fff4dd line. labelRotation keeps
    # "10-18 v0.9.7 1.15-DEV" apart. A missing sample is null, so the line breaks.
    # The series block is concatenated so every line keeps the same indent.
    head = """
    ```mermaid
    ---
    config:
      theme: base
      themeVariables:
        xyChart:
          plotColorPalette: "$palette"
      xyChart:
        xAxis:
          labelRotation: 45
    ---
    xychart-beta
        title "$title"
        x-axis [$xs]
        y-axis "seconds" 0 --> $ymax
    """
    return head * body * "\n```\n"
end

function method_table(prev, cur, name::String)::String
    after = top_map(cur, name)
    isempty(after) && return ""
    before = prev === nothing ? Dict{String, Float64}() : top_map(prev, name)
    lines = String["| method | now ms | previous ms |", "| --- | ---: | ---: |"]
    ranked = sort(collect(after); by = pair -> pair[2], rev = true)
    for (sig, ms) in ranked[1:min(10, end)]
        short = replace(sig, '|' => '/')
        length(short) > 90 && (short = short[1:90] * "...")
        old = get(before, sig, nothing)
        was = old === nothing ? "" : fnum(old)
        push!(lines, "| `$short` | $(fnum(ms)) | $was |")
    end
    return join(lines, "\n")
end

function slot_section(slot::String, rows)::Tuple{String, Vector{String}}
    shown = rows[max(1, end - 11):end]
    latest = shown[end]
    prev = length(shown) >= 2 ? shown[end - 1] : nothing
    flagged = flags_for(prev, latest)
    names = command_names(shown)
    cols = ["date", "commit", "version", "julia", "os", "arch", "src files", "code lines", "full s", "pkg s", "using s"]
    append!(cols, [name * " s" for name in names])
    header = "| " * join(cols, " | ") * " |"
    sep = "| " * join(fill("---", length(cols)), " | ") * " |"
    body = String[]
    for row in shown
        sha = string(get(row, "commit", ""))
        short = isempty(sha) ? "" : sha[1:min(7, end)]
        stamp = string(get(row, "time", ""))
        day = length(stamp) >= 10 ? stamp[1:10] : stamp
        cells = String[
            day,
            short,
            string(get(row, "version", "")),
            replace(string(get(row, "julia", "")), '|' => '/'),
            replace(string(get(row, "os_name", get(row, "os", ""))), '|' => '/'),
            replace(string(get(row, "arch", "")), '|' => '/'),
            inum(row, "src_files"),
            inum(row, "src_code_lines"),
            fnum(get(row, "precompile_full_sec", nothing)),
            fnum(get(row, "precompile_pkg_sec", nothing)),
            fnum(get(row, "using_sec", nothing)),
        ]
        for name in names
            wall = command_wall(row, name)
            push!(cells, wall === nothing ? "" : fnum(wall))
        end
        push!(body, "| " * join(cells, " | ") * " |")
    end
    parts = String["## $slot", "", header, sep]
    append!(parts, body)
    parts = append!(parts, [""])
    for band in chart_bands(names, shown)
        picture = chart(slot, band, shown)
        isempty(picture) && continue
        push!(parts, picture)
        push!(parts, "")
    end
    for name in names
        table = method_table(prev, latest, name)
        isempty(table) && continue
        push!(parts, "Latest `$name` methods:", "")
        push!(parts, table)
        push!(parts, "")
    end
    return (join(parts, "\n"), flagged)
end

function render(groups)::Tuple{String, Vector{String}}
    all_flags = String[]
    sections = String[]
    for slot in sort(collect(keys(groups)))
        text, flagged = slot_section(slot, groups[slot])
        push!(sections, text)
        for item in flagged
            push!(all_flags, "$slot: $item")
        end
    end
    flag_block = if isempty(all_flags)
        "No sample grew past the watch line."
    else
        join(["- " * item for item in all_flags], "\n")
    end
    readme = """
    # Compile bench

    Precompile time, load time, CLI wall time, `src/**/*.jl` size, and the host
    (OS name, arch, CPU). `code lines` skips blank lines. A row is flagged when,
    against the previous sample on the same Julia slot, the host OS or arch
    changes, the Julia version changes, package precompile grows by 1.5x and 0.5s, a command wall grows
    by 1.5x and 1s, or a method of at least 200 ms is new in the top 20 or
    doubles. This does not fail CI.

    ## Flagged

    $flag_block

    $(join(sections, "\n"))
    """
    return (readme, all_flags)
end

function main()
    history = arg_value("--history")
    readme = arg_value("--readme")
    summary = optional_arg("--summary")
    text, flagged = render(load_history(history))
    open(readme, "w") do io
        write(io, text)
    end
    if summary !== nothing
        open(summary, "a") do io
            println(io, "## Compile bench")
            if isempty(flagged)
                println(io, "No sample grew past the watch line.")
            else
                for item in flagged
                    println(io, "- ", item)
                end
            end
        end
    end
    println(stderr, "wrote ", readme)
    return nothing
end

main()
