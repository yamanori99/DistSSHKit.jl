# Interactive bench page. Included from report.jl `main` only.
# Stdlib only. plotly.js is loaded by the page, not by Julia.

function json_escape(text::AbstractString)::String
    out = IOBuffer()
    for char in text
        if char == '"'
            print(out, "\\\"")
        elseif char == '\\'
            print(out, "\\\\")
        elseif char == '\n'
            print(out, "\\n")
        elseif char == '\r'
            print(out, "\\r")
        elseif char == '<'
            print(out, "\\u003c")
        else
            print(out, char)
        end
    end
    return String(take!(out))
end

function json_encode(value)::String
    value === nothing && return "null"
    value isa Bool && return value ? "true" : "false"
    value isa Integer && return string(value)
    value isa AbstractFloat && return string(value)
    if value isa AbstractString
        return "\"" * json_escape(value) * "\""
    end
    if value isa AbstractDict
        parts = String[]
        for (key, item) in value
            push!(parts, json_encode(string(key)) * ":" * json_encode(item))
        end
        return "{" * join(parts, ",") * "}"
    end
    if value isa AbstractVector
        return "[" * join((json_encode(item) for item in value), ",") * "]"
    end
    error("cannot encode $(typeof(value))")
end

function html_escape(text)::String
    return replace(
        string(text),
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
    )
end

# Same rule as measure.jl. Old rows have no `owner`, so the page derives it.
function method_owner(signature::AbstractString, bucket::AbstractString)::String
    sig = string(signature)
    occursin("typeof(Main.", sig) && return "Main"
    if bucket in ("DistSSHKit", "DistSSHQueue", "DistSSHRun", "Base")
        return string(bucket)
    end
    matches = collect(eachmatch(r"typeof\(([A-Za-z_][A-Za-z0-9_]*)\.", sig))
    for item in Iterators.reverse(matches)
        name = string(something(item.captures[1], ""))
        name == "Main" && return "Main"
        name in ("Core", "") && continue
        return name
    end
    found = Base.match(r"(?:Tuple\{|, )([A-Z][A-Za-z0-9_]*)\.", sig)
    found === nothing && return string(bucket)
    return string(something(found.captures[1], bucket))
end

function julia_short(row)::String
    julia = strip(string(get(row, "julia", "")))
    isempty(julia) && return ""
    version = tryparse(VersionNumber, julia)
    version === nothing && return julia
    base = string(version.major, ".", version.minor)
    isempty(version.prerelease) && return base
    return base * "-" * string(version.prerelease[1])
end

function julia_patch(row)::String
    julia = strip(string(get(row, "julia", "")))
    isempty(julia) && return ""
    version = tryparse(VersionNumber, julia)
    version === nothing && return ""
    return string(version.major, ".", version.minor, ".", version.patch)
end

# `Ubuntu 24.04.3 LTS` is `Ubuntu 24.04`. A point release is not a new host.
function host_mark(row)::String
    haskey(row, "os_name") || return ""
    os = strip(string(row["os_name"]))
    isempty(os) && return ""
    found = Base.match(r"^([A-Za-z]+)\s+(\d+)\.(\d+)", os)
    label = found === nothing ? first(split(os)) : "$(found.captures[1]) $(found.captures[2]).$(found.captures[3])"
    arch = strip(string(get(row, "arch", "")))
    return isempty(arch) ? label : label * " " * arch
end

function bare_short(signature::AbstractString)::String
    matches = collect(eachmatch(r"typeof\(([A-Za-z_][A-Za-z0-9_.!]*)\)", signature))
    picked = ""
    for item in matches
        name = string(something(item.captures[1], ""))
        name == "Core.kwcall" && continue
        picked = name
    end
    isempty(picked) || return picked
    generated = Base.match(r"([A-Z][A-Za-z0-9_]*)\.var\"#([^#\"]+)", signature)
    generated === nothing || return "$(generated.captures[1]).$(generated.captures[2])"
    found = Base.match(r"Tuple\{([A-Z][A-Za-z0-9_]*)\.", signature)
    found === nothing && return signature
    return string(something(found.captures[1], signature))
end

function stored_methods(cmd)::Vector
    haskey(cmd, "methods") && return cmd["methods"]
    return get(cmd, "top", [])
end

function common_prefix_length(group::Vector{String})::Int
    isempty(group) && return 0
    chars = collect.(group)
    limit = minimum(length, chars)
    n = 0
    for i in 1:limit
        char = chars[1][i]
        all(item -> item[i] == char, chars) || break
        n = i
    end
    return n
end

# The part of a signature that is not shared with the other methods of the
# same name. `Serialization.deserialize` otherwise keeps only
# `Tuple{typeof(Serialization.deser` for every specialization.
function argument_tail(signature::AbstractString, prefix::Int)::String
    rest = signature
    i = firstindex(rest)
    for _ in 1:prefix
        i > lastindex(rest) && return ""
        i = nextind(rest, i)
    end
    rest = i > lastindex(rest) ? "" : rest[i:end]
    rest = replace(rest, r"^[,\s]+" => "")
    extra = count(==('}'), rest) - count(==('{'), rest)
    while extra > 0 && endswith(rest, '}')
        rest = rest[1:prevind(rest, lastindex(rest))]
        extra -= 1
    end
    return strip(rest)
end

function method_records(items)::Vector{Dict{String, Any}}
    shorts = String[]
    owners = String[]
    sigs = String[]
    for item in items
        sig = string(get(item, "signature", ""))
        push!(sigs, sig)
        push!(shorts, bare_short(sig))
        owner = haskey(item, "owner") ? string(item["owner"]) : method_owner(sig, string(get(item, "bucket", "")))
        push!(owners, owner)
    end
    groups = Dict{String, Vector{String}}()
    for (short, sig) in zip(shorts, sigs)
        push!(get!(groups, short, String[]), sig)
    end
    out = Dict{String, Any}[]
    for (index, item) in enumerate(items)
        short = shorts[index]
        group = groups[short]
        if length(group) > 1
            tail = argument_tail(sigs[index], common_prefix_length(group))
            isempty(tail) || (short = short * " " * tail)
        end
        push!(
            out, Dict{String, Any}(
                "signature" => sigs[index],
                "short" => short,
                "owner" => owners[index],
                "ms" => Float64(item["ms"]),
            )
        )
    end
    return out
end

function dep_payload(row)::Vector{Dict{String, Any}}
    raw = get(row, "deps", nothing)
    raw isa AbstractVector || return Dict{String, Any}[]
    out = Dict{String, Any}[]
    for item in raw
        item isa AbstractDict || continue
        name = strip(string(get(item, "name", "")))
        isempty(name) && continue
        rec = Dict{String, Any}("name" => name)
        ver = strip(string(get(item, "version", "")))
        tree = strip(string(get(item, "tree", "")))
        isempty(ver) || (rec["version"] = ver)
        isempty(tree) || (rec["tree"] = tree)
        push!(out, rec)
    end
    return out
end

function bench_payload(groups::Dict{String, Vector{Dict{String, Any}}})::Vector{Dict{String, Any}}
    slots = Dict{String, Any}[]
    for name in sort(collect(keys(groups)))
        samples = Dict{String, Any}[]
        for row in groups[name]
            sha = string(get(row, "commit", ""))
            commands = Dict{String, Any}[]
            for cmd in get(row, "commands", [])
                haskey(cmd, "wall_sec") || continue
                push!(
                    commands, Dict{String, Any}(
                        "name" => string(get(cmd, "name", "")),
                        "wall" => Float64(cmd["wall_sec"]),
                        "total" => haskey(cmd, "total_ms") ? Float64(cmd["total_ms"]) : nothing,
                        "methods" => method_records(stored_methods(cmd)),
                    )
                )
            end
            sample = Dict{String, Any}(
                "time" => string(get(row, "time", "")),
                "commit" => isempty(sha) ? "" : first(sha, 7),
                "julia" => string(get(row, "julia", "")),
                "julia_short" => julia_short(row),
                "julia_patch" => julia_patch(row),
                "version" => string(get(row, "version", "")),
                "host" => host_mark(row),
                "commands" => commands,
            )
            deps = dep_payload(row)
            isempty(deps) || (sample["deps"] = deps)
            push!(samples, sample)
        end
        push!(slots, Dict{String, Any}("name" => name, "samples" => samples))
    end
    return slots
end

function fallback_rows(payload::Vector{Dict{String, Any}})::String
    isempty(payload) && return "<p>No samples.</p>"
    index = findfirst(item -> item["name"] == "1.13", payload)
    slot = index === nothing ? payload[1] : payload[index]
    samples = slot["samples"]::Vector{Dict{String, Any}}
    isempty(samples) && return "<p>No samples.</p>"
    latest = samples[end]
    commands = latest["commands"]::Vector{Dict{String, Any}}
    isempty(commands) && return "<p>No commands.</p>"
    command = commands[argmax([Float64(item["wall"]) for item in commands])]
    methods = sort(command["methods"]; by = item -> Float64(item["ms"]), rev = true)
    shown = methods[1:min(8, end)]
    lines = String[]
    if get(command, "total", nothing) !== nothing
        sentence = "Compile total $(round(Int, command["total"])) ms"
        if length(samples) >= 2
            earlier = samples[end - 1]["commands"]::Vector{Dict{String, Any}}
            index = findfirst(item -> item["name"] == command["name"], earlier)
            if index !== nothing && get(earlier[index], "total", nothing) !== nothing
                delta = round(Int, command["total"]) - round(Int, earlier[index]["total"])
                signed = delta > 0 ? "+$delta" : string(delta)
                sentence *= ", $signed ms"
            end
        end
        push!(lines, "<p>$(sentence).</p>")
    end
    push!(lines, "<table>")
    push!(lines, "<tr><th>owner</th><th>method</th><th>ms</th></tr>")
    for item in shown
        push!(lines, "<tr><td>$(html_escape(item["owner"]))</td><td>$(html_escape(item["short"]))</td><td>$(html_escape(item["ms"]))</td></tr>")
    end
    push!(lines, "</table>")
    push!(lines, "<table>")
    push!(lines, "<tr><th>command</th><th>now s</th></tr>")
    for item in commands
        push!(lines, "<tr><td>$(html_escape(item["name"]))</td><td>$(html_escape(item["wall"]))</td></tr>")
    end
    push!(lines, "</table>")
    return join(lines, "\n")
end

const PAGE_SCRIPT = raw"""
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<script>
const SLOTS = DATA;
const RANGES = [
  ["7d", 7],
  ["30d", 30],
  ["6mo", 183],
  ["1y", 365],
  ["2y", 730],
  ["all", null]
];
const PACKAGE = new Set(["DistSSHKit", "DistSSHRun", "DistSSHQueue"]);
const state = { slot: "", range: "30d", n: 8, cmd: "", drag: null };

function slotData() {
  return SLOTS.find((item) => item.name === state.slot) || SLOTS[0];
}

function parseTime(text) {
  const value = Date.parse(text);
  return Number.isNaN(value) ? 0 : value;
}

function visibleSamples() {
  const slot = slotData();
  const samples = slot ? slot.samples : [];
  if (!samples.length) return [];
  const latest = parseTime(samples[samples.length - 1].time);
  let start = 0;
  let end = latest;
  if (state.drag) {
    start = state.drag[0];
    end = state.drag[1];
  } else if (state.range !== "all") {
    const days = RANGES.find((item) => item[0] === state.range)[1];
    start = latest - days * 86400000;
  } else {
    start = parseTime(samples[0].time);
  }
  return samples.filter((sample) => {
    const time = parseTime(sample.time);
    return time >= start && time <= end + 1000;
  });
}

function commandNames(samples) {
  const names = [];
  samples.forEach((sample) => {
    sample.commands.forEach((command) => {
      if (!names.includes(command.name)) names.push(command.name);
    });
  });
  return names;
}

function wallAt(sample, name) {
  const command = sample.commands.find((item) => item.name === name);
  return command ? command.wall : null;
}

function ranked(command) {
  return command.methods.slice().sort((a, b) => b.ms - a.ms);
}

function chartMethods(samples, count) {
  const picked = [];
  const seen = new Set();
  for (let index = samples.length - 1; index >= 0; index -= 1) {
    const command = samples[index].commands.find((item) => item.name === state.cmd);
    if (!command) continue;
    ranked(command).slice(0, count).forEach((method) => {
      if (seen.has(method.signature)) return;
      seen.add(method.signature);
      picked.push({
        signature: method.signature,
        short: method.short,
        owner: method.owner
      });
    });
  }
  return picked;
}

function defaultCommand(samples) {
  const names = commandNames(samples);
  let best = names[0] || "";
  let bestWall = -1;
  for (let index = samples.length - 1; index >= 0; index -= 1) {
    names.forEach((name) => {
      const wall = wallAt(samples[index], name);
      if (wall !== null && wall > bestWall) {
        bestWall = wall;
        best = name;
      }
    });
    if (bestWall >= 0) break;
  }
  return best;
}

function methodMs(sample, name, signature) {
  const command = sample.commands.find((item) => item.name === name);
  if (!command) return null;
  const found = command.methods.find((method) => method.signature === signature);
  return found ? found.ms : null;
}

function hoverMarks(samples, values) {
  let last = -1;
  for (let index = 0; index < values.length; index += 1) {
    if (values[index] !== null) last = index;
  }
  const slots = depSlots(samples);
  return samples.map((sample, index) => {
    const mark = sampleMark(sample, slots);
    mark.push(index === last ? "last" : "");
    return mark;
  });
}

function dropSpikes(values) {
  const out = values.slice();
  const notes = [];
  for (let index = 0; index < out.length - 1; index += 1) {
    if (out[index] === null) continue;
    let next = index + 1;
    while (next < out.length && out[next] === null) next += 1;
    if (next >= out.length) break;
    if (out[index] > 4 * out[next]) {
      notes.push(out[index]);
      out[index] = null;
    }
  }
  return { values: out, notes };
}

function breaks(samples, field, nightlyOnly) {
  const marks = [];
  if (nightlyOnly && !state.slot.includes("nightly")) return marks;
  for (let index = 1; index < samples.length; index += 1) {
    const previous = samples[index - 1][field];
    const current = samples[index][field];
    if (previous && current && previous !== current) {
      marks.push({ time: samples[index].time, label: current });
    }
  }
  return marks;
}

function patchMarks(samples) {
  if (state.slot !== "1.13") return [];
  return breaks(samples, "julia_patch", false);
}

function shapes(samples) {
  const julia = breaks(samples, "julia_short", true);
  const hosts = breaks(samples, "host", false);
  const cuts = breaks(samples, "version", false);
  const patches = patchMarks(samples);
  return julia.map((mark) => ({
    type: "line", x0: mark.time, x1: mark.time, y0: 0, y1: 1, yref: "paper",
    line: { dash: "dash", width: 1, color: "#64748b" }
  })).concat(hosts.map((mark) => ({
    type: "line", x0: mark.time, x1: mark.time, y0: 0, y1: 1, yref: "paper",
    line: { dash: "dot", width: 1, color: "#9558b2" }
  }))).concat(cuts.map((mark) => ({
    type: "line", x0: mark.time, x1: mark.time, y0: 0, y1: 1, yref: "paper",
    line: { width: 1, color: "#c2410c" }
  }))).concat(patches.map((mark) => ({
    type: "line", x0: mark.time, x1: mark.time, y0: 0, y1: 1, yref: "paper",
    line: { dash: "dashdot", width: 1, color: "#0369a1" }
  })));
}

function eventRows(samples) {
  const rows = [];
  function push(kind, marks) {
    marks.forEach((mark) => rows.push({ time: mark.time, kind, text: mark.label }));
  }
  push("julia", breaks(samples, "julia_short", true));
  push("host", breaks(samples, "host", false));
  push("version", breaks(samples, "version", false));
  push("patch", patchMarks(samples));
  rows.sort((a, b) => parseTime(a.time) - parseTime(b.time));
  return rows;
}

const EVENT_COLOR = { julia: "#64748b", host: "#9558b2", version: "#c2410c", patch: "#0369a1" };

function labelSpan(samples, width, node) {
  const axis = node && node._fullLayout && node._fullLayout.xaxis;
  if (axis && axis.range && axis._length > 0) {
    const start = parseTime(axis.range[0]);
    const end = parseTime(axis.range[1]);
    if (end > start) return { t0: start, span: end - start, innerW: axis._length };
  }
  const t0 = samples.length ? parseTime(samples[0].time) : 0;
  const t1 = samples.length ? parseTime(samples[samples.length - 1].time) : t0;
  return { t0, span: Math.max(t1 - t0, 1), innerW: Math.max(40, (width || 560) - 64) };
}

function labelAnnotations(samples, width, node) {
  const rows = eventRows(samples);
  if (!rows.length) return [];
  const span = labelSpan(samples, width, node);
  const charPx = 7.2;
  const gap = 8;
  const rowH = 24;
  const ends = [];
  return rows.map((row) => {
    const xPx = ((parseTime(row.time) - span.t0) / span.span) * span.innerW;
    const textW = Math.max(charPx, charPx * String(row.text).length);
    const start = xPx - textW / 2;
    let tier = 0;
    while (ends[tier] != null && ends[tier] + gap > start) tier += 1;
    ends[tier] = xPx + textW / 2;
    return {
      x: row.time,
      xref: "x",
      y: 1,
      yref: "paper",
      yshift: -(tier * rowH + 2),
      text: row.text,
      showarrow: false,
      xanchor: "center",
      yanchor: "top",
      font: { size: 12, color: EVENT_COLOR[row.kind] || "#334155" }
    };
  });
}

function refineLabels(node, samples) {
  if (!window.Plotly || !node) return Promise.resolve();
  return Plotly.relayout(node, {
    annotations: labelAnnotations(samples, node.clientWidth || 560, node)
  });
}

function paintEvents(id, samples) {
  const host = document.getElementById(id);
  host.replaceChildren();
  const rows = eventRows(samples);
  if (!rows.length) return;
  const title = document.createElement("p");
  title.className = "events-title";
  title.textContent = "Events in this range";
  host.appendChild(title);
  rows.forEach((row) => {
    const line = document.createElement("p");
    line.dataset.kind = row.kind;
    const when = String(row.time).slice(0, 16).replace("T", " ");
    line.textContent = when + "  " + row.kind + "  " + row.text;
    host.appendChild(line);
  });
}

function depParts(sample, withTree) {
  const deps = (sample && sample.deps) || [];
  const parts = [];
  deps.forEach((dep) => {
    if (!dep || !dep.name || !dep.version) return;
    let text = String(dep.name) + " " + String(dep.version);
    if (withTree && dep.tree) text += " " + String(dep.tree).slice(0, 7);
    parts.push(text);
  });
  return parts;
}

function depLine(sample, withTree) {
  return depParts(sample, withTree).join(", ");
}

function depSlots(samples) {
  let count = 0;
  samples.forEach((sample) => {
    const n = depParts(sample, true).length;
    if (n > count) count = n;
  });
  return count;
}

function sampleMark(sample, slots) {
  const row = [
    String(sample.time).slice(0, 10),
    String(sample.commit || ""),
    String(sample.julia || ""),
    String(sample.version || ""),
    String(sample.host || "")
  ];
  const parts = depParts(sample, true);
  for (let index = 0; index < slots; index += 1) row.push(parts[index] || "");
  return row;
}

function hoverTail(slots) {
  let text = "%{customdata[3]} %{customdata[4]}";
  for (let index = 0; index < slots; index += 1) {
    text += "<br>%{customdata[" + (5 + index) + "]}";
  }
  return text;
}

function paintDeps(id, samples) {
  const node = document.getElementById(id);
  const latest = samples.length ? samples[samples.length - 1] : null;
  node.textContent = latest ? depLine(latest, false) : "";
}

const COLORWAY = ["#636efa", "#EF553B", "#00cc96", "#ab63fa", "#FFA15A", "#19d3f3", "#FF6692", "#B6E880", "#FF97FF", "#FECB52"];

function paintKey(id, names) {
  const host = document.getElementById(id);
  host.replaceChildren();
  names.forEach((name, index) => {
    const row = document.createElement("div");
    const swatch = document.createElement("i");
    swatch.style.background = COLORWAY[index % COLORWAY.length];
    const text = document.createElement("span");
    text.textContent = name;
    row.appendChild(swatch);
    row.appendChild(text);
    host.appendChild(row);
  });
}

function layout(title, ytitle, samples, width) {
  const height = title.startsWith("Method") ? 400 : 280;
  return {
    title, width, height,
    margin: { t: 36, r: 16, b: 48, l: 48 },
    xaxis: { type: "date", automargin: true, tickformat: "%Y-%m-%d" },
    yaxis: { title: ytitle, rangemode: "tozero", automargin: true },
    shapes: shapes(samples),
    annotations: labelAnnotations(samples, width, null),
    colorway: COLORWAY,
    showlegend: false,
    hovermode: "closest"
  };
}

function drawWall(samples) {
  const names = commandNames(samples);
  const notes = [];
  const slots = depSlots(samples);
  const wallHover = "%{customdata[0]} %{customdata[1]}<br>%{fullData.name} %{y} s<br>" + hoverTail(slots) + "<extra></extra>";
  const traces = names.map((name) => {
    const raw = samples.map((sample) => wallAt(sample, name));
    const dropped = dropSpikes(raw);
    dropped.notes.forEach((value) => notes.push(name + " " + value + "s omitted"));
    return {
      type: "scatter", mode: "lines+markers", name, connectgaps: false,
      marker: { size: 2 },
      x: samples.map((sample) => sample.time),
      y: dropped.values,
      customdata: samples.map((sample) => sampleMark(sample, slots)),
      hovertemplate: wallHover
    };
  });
  paintKey("wall-key", names);
  const node = document.getElementById("wall-chart");
  const wallLayout = layout("Command wall", "seconds", samples, node.clientWidth || 560);
  const drawn = window.Plotly ? Plotly.react(node, traces, wallLayout).then(() => refineLabels(node, samples)) : Promise.resolve();
  if (window.Plotly) {
    if (node.removeAllListeners) node.removeAllListeners("plotly_click");
    node.on("plotly_click", (event) => {
      const point = event.points && event.points[0];
      if (!point) return;
      state.cmd = names[point.curveNumber];
      state.drag = null;
      draw();
    });
  }
  document.getElementById("wall-note").textContent = notes.join(" ");
  paintDeps("wall-deps", samples);
  window.__wallDrawn = drawn;
  const body = document.querySelector("#wall-table tbody");
  body.innerHTML = "";
  names.forEach((name) => {
    const values = samples.map((sample) => wallAt(sample, name));
    const present = values.filter((value) => value !== null);
    const row = document.createElement("tr");
    const now = values.length ? values[values.length - 1] : null;
    const start = present.length ? present[0] : null;
    const change = now === null || start === null || present.length < 2 ? "" : (now - start).toFixed(2);
    [name, now === null ? "" : now.toFixed(2), start === null ? "" : start.toFixed(2), change].forEach((cell) => {
      const td = document.createElement("td");
      td.textContent = cell;
      row.appendChild(td);
    });
    body.appendChild(row);
  });
}

function drawMethods(samples) {
  const available = new Set();
  samples.forEach((sample) => {
    const command = sample.commands.find((item) => item.name === state.cmd);
    if (command) command.methods.forEach((method) => available.add(method.signature));
  });
  const cap = Math.max(1, available.size);
  if (state.n > cap) state.n = cap;
  const series = chartMethods(samples, state.n);
  const slots = depSlots(samples);
  const methodHover = "%{customdata[0]} %{customdata[1]}<br>%{fullData.name}<br>%{y} ms %{customdata[" + (5 + slots) + "]}<br>" + hoverTail(slots) + "<extra></extra>";
  const traces = series.map((method) => {
    const ys = samples.map((sample) => methodMs(sample, state.cmd, method.signature));
    return {
      type: "scatter", mode: "lines+markers", name: method.short, connectgaps: false,
      marker: { size: 2 },
      x: samples.map((sample) => sample.time),
      y: ys,
      customdata: hoverMarks(samples, ys),
      hovertemplate: methodHover
    };
  });
  paintKey("method-key", series.map((method) => method.short));
  const node = document.getElementById("method-chart");
  const methodLayout = layout("Method rank", "ms", samples, node.clientWidth || 560);
  const drawn = window.Plotly ? Plotly.react(node, traces, methodLayout).then(() => refineLabels(node, samples)) : Promise.resolve();
  window.__methodDrawn = drawn;
  const body = document.querySelector("#method-table tbody");
  body.innerHTML = "";
  const latest = samples[samples.length - 1];
  const prev = samples.length > 1 ? samples[samples.length - 2] : null;
  function top(sample) {
    if (!sample) return [];
    const command = sample.commands.find((item) => item.name === state.cmd);
    return command ? ranked(command).slice(0, state.n) : [];
  }
  const now = top(latest);
  const before = top(prev);
  function rankOf(list, signature) {
    const index = list.findIndex((item) => item.signature === signature);
    return index < 0 ? 0 : index + 1;
  }
  now.forEach((method) => {
    const nowRank = rankOf(now, method.signature);
    const prevRank = rankOf(before, method.signature);
    const old = prevRank ? before[prevRank - 1] : null;
    const row = document.createElement("tr");
    if (PACKAGE.has(method.owner)) row.dataset.package = "1";
    const delta = old ? method.ms - old.ms : "";
    [nowRank, prevRank || "", prevRank ? String(prevRank - nowRank) : "new", method.owner, method.short, Math.round(method.ms), delta === "" ? "" : Math.round(delta)].forEach((cell) => {
      const td = document.createElement("td");
      td.textContent = cell;
      row.appendChild(td);
    });
    body.appendChild(row);
  });
  paintDeps("method-deps", samples);
  document.getElementById("method-count").textContent = String(state.n);
  document.getElementById("method-note").textContent =
    state.slot + " methods for " + state.cmd + ".";
  const latestCommand = latest.commands.find((item) => item.name === state.cmd) || null;
  const nowTotal = latestCommand && latestCommand.total != null ? latestCommand.total : null;
  const prevCommand = prev ? prev.commands.find((item) => item.name === state.cmd) : null;
  const prevTotal = prevCommand && prevCommand.total != null ? prevCommand.total : null;
  const totalNode = document.getElementById("method-total");
  if (nowTotal == null) {
    totalNode.textContent = "";
  } else if (prevTotal == null) {
    totalNode.textContent = "Compile total " + Math.round(nowTotal) + " ms.";
  } else {
    const delta = Math.round(nowTotal) - Math.round(prevTotal);
    const signed = delta > 0 ? "+" + delta : String(delta);
    totalNode.textContent = "Compile total " + Math.round(nowTotal) + " ms, " + signed + " ms.";
  }
}

function drawControls() {
  const slots = document.getElementById("slots");
  slots.innerHTML = "";
  SLOTS.forEach((slot) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = slot.name;
    button.setAttribute("aria-pressed", slot.name === state.slot ? "true" : "false");
    button.onclick = () => { state.slot = slot.name; state.cmd = ""; state.drag = null; draw(); };
    slots.appendChild(button);
  });
  document.getElementById("range-label").textContent = state.drag ? "drag" : state.range;
}

function writeQuery() {
  const query = new URLSearchParams();
  query.set("slot", state.slot);
  query.set("range", state.range);
  query.set("n", String(state.n));
  query.set("cmd", state.cmd);
  history.replaceState(null, "", "?" + query.toString());
}

function draw() {
  const samples = visibleSamples();
  if (!samples.length) return;
  if (!commandNames(samples).includes(state.cmd)) state.cmd = defaultCommand(samples);
  drawControls();
  drawing += 1;
  drawMethods(samples);
  drawWall(samples);
  paintEvents("method-events", samples);
  paintEvents("wall-events", samples);
  state.shown = samples.map((sample) => sample.time).join("|");
  Promise.all([window.__methodDrawn, window.__wallDrawn]).then(() => { drawing -= 1; });
  writeQuery();
  if (!window.Plotly) return;
  const wall = document.getElementById("wall-chart");
  const method = document.getElementById("method-chart");
  function follow(event) {
    if (drawing > 0) return;
    if (!event || event["xaxis.autorange"]) return;
    const start = Date.parse(event["xaxis.range[0]"]);
    const end = Date.parse(event["xaxis.range[1]"]);
    if (Number.isNaN(start) || Number.isNaN(end)) return;
    state.drag = [start, end];
    const key = visibleSamples().map((sample) => sample.time).join("|");
    if (key === state.shown) return;
    draw();
  }
  [wall, method].forEach((node) => {
    if (!node.removeAllListeners) return;
    node.removeAllListeners("plotly_relayout");
    node.on("plotly_relayout", follow);
  });
}

let drawing = 0;
function boot() {
  const fallback = document.getElementById("fallback");
  if (fallback) fallback.hidden = true;
  const query = new URLSearchParams(location.search);
  const names = SLOTS.map((slot) => slot.name);
  state.slot = names.includes(query.get("slot")) ? query.get("slot") : (names.includes("1.13") ? "1.13" : names[0]);
  const range = query.get("range");
  state.range = RANGES.some((item) => item[0] === range) ? range : "30d";
  const count = Number(query.get("n"));
  state.n = count >= 1 ? Math.round(count) : 8;
  state.cmd = query.get("cmd") || "";
  document.getElementById("range-dec").onclick = () => {
    const index = Math.max(0, RANGES.findIndex((item) => item[0] === state.range) - 1);
    state.range = RANGES[index][0];
    state.drag = null;
    draw();
  };
  document.getElementById("range-inc").onclick = () => {
    const index = RANGES.findIndex((item) => item[0] === state.range);
    state.range = RANGES[Math.min(RANGES.length - 1, index + 1)][0];
    state.drag = null;
    draw();
  };
  document.getElementById("method-dec").onclick = () => { state.n = Math.max(1, state.n - 1); draw(); };
  document.getElementById("method-inc").onclick = () => { state.n += 1; draw(); };
  draw();
}
boot();
</script>
"""

function bench_html(groups)::String
    payload = bench_payload(groups)
    tables = fallback_rows(payload)
    script = replace(PAGE_SCRIPT, "const SLOTS = DATA;" => "const SLOTS = " * json_encode(payload) * ";")
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>Compile bench</title>
    <style>
    body { font: 15px/1.4 sans-serif; margin: 24px auto; max-width: 920px; padding: 0 16px; color: #0f172a; background: #fff; }
    button { margin: 0 4px 8px 0; }
    button[aria-pressed="true"] { font-weight: 700; }
    .chart-row { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 12px 16px; }
    .plot { flex: 0 0 560px; width: 560px; max-width: 100%; }
    .key { flex: 1 1 14rem; min-width: 12rem; max-width: 22rem; }
    .key div { display: flex; gap: 8px; align-items: flex-start; margin: 0 0 6px; }
    .key i { flex: 0 0 12px; width: 12px; height: 12px; margin-top: 4px; }
    .key span { overflow-wrap: anywhere; }
    table { border-collapse: collapse; margin: 12px 0 24px; width: 100%; table-layout: fixed; }
    td, th { border: 1px solid #cbd5e1; padding: 4px 8px; text-align: left; overflow-wrap: anywhere; }
    tr[data-package="1"] { background: #f3e8ff; }
    #range-row, #method-row { margin: 8px 0 16px; }
    .events { margin: 0 0 16px; color: #334155; font-size: 13px; }
    .events p { margin: 0 0 2px; }
    .events-title { color: #64748b; }
    .events p[data-kind="host"] { color: #9558b2; }
    .events p[data-kind="version"] { color: #c2410c; }
    .events p[data-kind="patch"] { color: #0369a1; }
    #method-deps, #wall-deps { margin: 0 0 8px; }
    #method-deps:empty, #wall-deps:empty { display: none; }
    </style>
    </head>
    <body>
    <div id="slots"></div>
    <div id="range-row">
    <span>range</span>
    <button type="button" id="range-dec">-</button>
    <span id="range-label">30d</span>
    <button type="button" id="range-inc">+</button>
    </div>
    <h1>Method rank</h1>
    <div id="method-row">
    <span>methods</span>
    <button type="button" id="method-dec">-</button>
    <span id="method-count">8</span>
    <button type="button" id="method-inc">+</button>
    </div>
    <p>A time is a specialization this command compiled. Specializations of this package are all kept. Any other owner is kept only at 200 ms or more. Main, the driving script, is omitted. This is not every method under <code>src/</code>. Each function is one name. When one of its methods compiles, the methods that did not compile are left out.</p>
    <div class="chart-row">
    <div id="method-chart" class="plot"></div>
    <div id="method-key" class="key"></div>
    </div>
    <div class="events" id="method-events"></div>
    <p id="method-note"></p>
    <p id="method-total"></p>
    <p id="method-deps"></p>
    <table id="method-table">
    <colgroup><col style="width:3.5rem"><col style="width:3.5rem"><col style="width:9.5rem"><col style="width:8rem"><col><col style="width:4.5rem"><col style="width:5.5rem"></colgroup>
    <thead><tr><th>now</th><th>prev</th><th>change</th><th>owner</th><th>method</th><th>ms</th><th>ms change</th></tr></thead>
    <tbody></tbody>
    </table>
    <h2>Command wall</h2>
    <div class="chart-row">
    <div id="wall-chart" class="plot"></div>
    <div id="wall-key" class="key"></div>
    </div>
    <div class="events" id="wall-events"></div>
    <p id="wall-note"></p>
    <p id="wall-deps"></p>
    <table id="wall-table">
    <thead><tr><th>command</th><th>now s</th><th>start s</th><th>change</th></tr></thead>
    <tbody></tbody>
    </table>
    <div id="fallback">
    $tables
    </div>
    $script
    </body>
    </html>
    """
end

function write_bench(groups, path::AbstractString)
    open(path, "w") do io
        write(io, bench_html(groups))
    end
    println(stderr, "wrote ", path)
    return nothing
end
