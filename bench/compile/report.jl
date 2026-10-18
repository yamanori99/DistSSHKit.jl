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

function chart(slot::String, name::String, rows)::String
    labels = String[]
    values = Float64[]
    for row in rows
        wall = command_wall(row, name)
        wall === nothing && continue
        t = string(get(row, "time", ""))
        label = length(t) >= 10 ? t[6:7] * t[9:10] : t
        push!(labels, label)
        push!(values, wall)
    end
    isempty(values) && return ""
    # A one-point line is a zero-length path, so GitHub draws an empty plot.
    series = length(values) == 1 ? "bar" : "line"
    ymax = max(1, ceil(Int, maximum(values) * 1.2))
    xs = join((string('"', x, '"') for x in labels), ", ")
    ys = join((string(round(v; digits = 2)) for v in values), ", ")
    return """
    ```mermaid
    xychart-beta
        title "$slot $name"
        x-axis [$xs]
        y-axis "seconds" 0 --> $ymax
        $series [$ys]
    ```
    """
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
    cols = ["date", "commit", "version", "os", "arch", "src files", "code lines", "full s", "pkg s", "using s"]
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
    for name in names
        picture = chart(slot, name, shown)
        isempty(picture) && continue
        push!(parts, picture)
        push!(parts, "")
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
    against the previous sample on the same Julia slot, package precompile grows
    by 1.5x and 0.5s,
    a command wall grows by 1.5x and 1s, or a method of at least 200 ms is new
    in the top 20 or doubles. This does not fail CI.

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
