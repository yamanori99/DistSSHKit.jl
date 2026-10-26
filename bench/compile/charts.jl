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
            push!(
                samples, Dict{String, Any}(
                    "time" => string(get(row, "time", "")),
                    "commit" => isempty(sha) ? "" : first(sha, 7),
                    "julia" => string(get(row, "julia", "")),
                    "julia_short" => julia_short(row),
                    "julia_patch" => julia_patch(row),
                    "version" => string(get(row, "version", "")),
                    "host" => host_mark(row),
                    "commands" => commands,
                )
            )
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

function measuredBefore(samples, index, signature) {
  if (index <= 0) return null;
  const command = samples[index - 1].commands.find((item) => item.name === state.cmd);
  if (!command) return null;
  const found = command.methods.find((method) => method.signature === signature);
  return found ? found.ms : null;
}

function chosenMethods(samples, count) {
  const picked = [];
  const seen = new Set();
  for (let index = samples.length - 1; index >= 0 && picked.length < count; index -= 1) {
    const command = samples[index].commands.find((item) => item.name === state.cmd);
    if (!command) continue;
    ranked(command).slice(0, count).forEach((method, place) => {
      if (picked.length >= count || seen.has(method.signature)) return;
      seen.add(method.signature);
      picked.push({
        signature: method.signature,
        short: method.short,
        owner: method.owner,
        ms: method.ms,
        prior: measuredBefore(samples, index, method.signature),
        when: String(samples[index].time).slice(0, 10),
        at: place + 1
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

function latestWithCommand(samples, name) {
  for (let index = samples.length - 1; index >= 0; index -= 1) {
    const command = samples[index].commands.find((item) => item.name === name);
    if (command) return { index, command };
  }
  return null;
}

function methodY(sample, name, signature, count) {
  const command = sample.commands.find((item) => item.name === name);
  if (!command) return null;
  const index = ranked(command).findIndex((method) => method.signature === signature);
  if (index < 0 || index >= count) return null;
  return ranked(command)[index].ms;
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

function sampleMark(sample) {
  return [
    String(sample.time).slice(0, 10),
    String(sample.commit || ""),
    String(sample.julia || ""),
    String(sample.version || ""),
    String(sample.host || "")
  ];
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
  return {
    title, width, height: title.startsWith("Method") ? 400 : 280,
    margin: { t: 36, r: 16, b: 48, l: 48 },
    xaxis: { type: "date", automargin: true, tickformat: "%Y-%m-%d" },
    yaxis: { title: ytitle, rangemode: "tozero", automargin: true },
    shapes: shapes(samples),
    colorway: COLORWAY,
    showlegend: false,
    hovermode: "closest"
  };
}

function drawWall(samples) {
  const names = commandNames(samples);
  const notes = [];
  const traces = names.map((name) => {
    const raw = samples.map((sample) => wallAt(sample, name));
    const dropped = dropSpikes(raw);
    dropped.notes.forEach((value) => notes.push(name + " " + value + "s omitted"));
    return {
      type: "scatter", mode: "lines+markers", name, connectgaps: false,
      x: samples.map((sample) => sample.time),
      y: dropped.values,
      customdata: samples.map(sampleMark),
      hovertemplate: "%{customdata[0]} %{customdata[1]}<br>%{fullData.name} %{y} s<br>%{customdata[3]} %{customdata[4]}<extra></extra>"
    };
  });
  paintKey("wall-key", names);
  const node = document.getElementById("wall-chart");
  const drawn = window.Plotly ? Plotly.react(node, traces, layout("Command wall", "seconds", samples, node.clientWidth || 560)) : Promise.resolve();
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
  window.__wallDrawn = drawn;
  const body = document.querySelector("#wall-table tbody");
  body.innerHTML = "";
  names.forEach((name) => {
    const values = samples.map((sample) => wallAt(sample, name)).filter((value) => value !== null);
    const row = document.createElement("tr");
    const now = values.length ? values[values.length - 1] : null;
    const start = values.length ? values[0] : null;
    const change = now === null || start === null || values.length < 2 ? "" : (now - start).toFixed(2);
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
  const found = latestWithCommand(samples, state.cmd);
  const chosen = chosenMethods(samples, state.n);
  if (chosen.length > 0 && state.n > chosen.length) state.n = chosen.length;
  const traces = chosen.map((method) => ({
    type: "scatter", mode: "lines+markers", name: method.short, connectgaps: false,
    x: samples.map((sample) => sample.time),
    y: samples.map((sample) => methodY(sample, state.cmd, method.signature, state.n)),
    customdata: samples.map(sampleMark),
    hovertemplate: "%{customdata[0]} %{customdata[1]}<br>%{fullData.name}<br>%{y} ms<br>%{customdata[3]} %{customdata[4]}<extra></extra>"
  }));
  paintKey("method-key", chosen.map((method) => method.short));
  const node = document.getElementById("method-chart");
  const drawn = window.Plotly ? Plotly.react(node, traces, layout("Method rank", "ms", samples, node.clientWidth || 560)) : Promise.resolve();
  window.__methodDrawn = drawn;
  const body = document.querySelector("#method-table tbody");
  body.innerHTML = "";
  const prev = found && found.index > 0 ? samples[found.index - 1] : null;
  function top(sample) {
    if (!sample) return [];
    const command = sample.commands.find((item) => item.name === state.cmd);
    return command ? ranked(command).slice(0, state.n) : [];
  }
  const now = found ? ranked(found.command).slice(0, state.n) : [];
  const before = top(prev);
  function rankOf(list, signature) {
    const index = list.findIndex((item) => item.signature === signature);
    return index < 0 ? 0 : index + 1;
  }
  const rows = chosen.map((method) => {
    const nowRank = rankOf(now, method.signature);
    const prevRank = rankOf(before, method.signature);
    const current = nowRank ? now[nowRank - 1] : null;
    const old = prevRank ? before[prevRank - 1] : null;
    const shown = current || method;
    let change = "";
    if (nowRank && prevRank) change = String(prevRank - nowRank);
    else if (nowRank) change = "new";
    else if (prevRank) change = "gone";
    else if (method.when) change = method.when + " #" + method.at;
    let delta = "";
    if (current && old) delta = current.ms - old.ms;
    else if (!nowRank && !prevRank && method.prior != null) delta = method.ms - method.prior;
    return {
      method: shown,
      nowRank: nowRank || "",
      prevRank: prevRank || "",
      change,
      ms: current ? current.ms : method.ms,
      delta
    };
  });
  before.forEach((method) => {
    if (chosen.some((item) => item.signature === method.signature)) return;
    const prevRank = before.findIndex((item) => item.signature === method.signature) + 1;
    rows.push({ method, nowRank: "", prevRank, change: "gone", ms: "", delta: "" });
  });
  rows.forEach((item) => {
    const row = document.createElement("tr");
    if (PACKAGE.has(item.method.owner)) row.dataset.package = "1";
    [item.nowRank, item.prevRank, item.change, item.method.owner, item.method.short, item.ms === "" ? "" : Math.round(item.ms), item.delta === "" ? "" : Math.round(item.delta)].forEach((cell) => {
      const td = document.createElement("td");
      td.textContent = cell;
      row.appendChild(td);
    });
    body.appendChild(row);
  });
  document.getElementById("method-count").textContent = String(state.n);
  document.getElementById("method-note").textContent =
    state.slot + " methods for " + state.cmd + ".";
  const nowTotal = found && found.command.total != null ? found.command.total : null;
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
