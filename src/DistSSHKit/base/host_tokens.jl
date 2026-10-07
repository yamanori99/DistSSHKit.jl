# Host lists and worker counts. Placement grammar stays in hosts.jl.

"""Split a `--hosts` / `DISTSSHKIT_HOSTS` CSV into tokens (empty pieces dropped)."""
function split_hosts_csv(raw::AbstractString)::Vector{String}
    out = String[]
    for h in split(String(raw), ',')
        s = strip(h)
        !isempty(s) && push!(out, s)
    end
    return out
end

"""
Parse `host` or `host:N` into `(hostname, workers)`.

`N` is a worker/slot count for `drive` / `go`. `setup` / `size` keep
the hostname only (`split_worker_token(…)[1]`).
"""
function split_worker_token(spec::AbstractString)::Tuple{String, Union{Nothing, Int}}
    s = strip(String(spec))
    if contains(s, ':')
        parts = split(s, ':', limit = 2)
        return String(parts[1]), parse(Int, parts[2])
    end
    return s, nothing
end

"""
    host_tokens(hosts::AbstractVector{<:AbstractString}) -> Vector{String}
    host_tokens(hosts::AbstractVector{Tuple{String,Union{Int,Nothing}}}; parent_workers=0)
    host_tokens(parsed; kind::Symbol) -> Vector{String}

Rebuild CLI host tokens for `execute!`.

Go tokens are the parser strings. Ride uses the same shape. Drive tuples plus
`parent_workers` emit `parent:N` then `child:NAME:N`. `kind` must be `:go`,
`:drive`, or `:ride`.
"""
function host_tokens(hosts::AbstractVector{<:AbstractString})::Vector{String}
    return String[String(h) for h in hosts]
end

function host_tokens(
        hosts::AbstractVector{Tuple{String, Union{Int, Nothing}}};
        parent_workers::Integer = 0,
    )::Vector{String}
    specs = String[]
    lw = Int(parent_workers)
    lw > 0 && push!(specs, format_placement_token(:parent, PARENT_HOST_NAME, lw))
    for pair in hosts
        host = pair[1]
        n = pair[2]
        push!(specs, format_placement_token(:child, host, n))
    end
    return specs
end

function host_tokens(parsed; kind::Symbol)::Vector{String}
    if kind === :go || kind === :ride
        return host_tokens(parsed.hosts::AbstractVector{<:AbstractString})
    elseif kind === :drive
        return host_tokens(
            parsed.hosts::AbstractVector{Tuple{String, Union{Int, Nothing}}};
            parent_workers = parsed.parent_workers,
        )
    end
    throw(ArgumentError("host_tokens: kind must be :go, :drive, or :ride, got $(repr(kind))"))
end

"""Non-comment host entries from a hosts file (may include `host:N` for drive/go)."""
function read_hosts_file_lines(
        path::AbstractString;
        surface::Symbol = :cli,
    )::Vector{String}
    p = canonical_local_path(path)
    isfile(p) || throw(ArgumentError(explain_hosts_file_not_found(p; surface = surface)))
    hosts = String[]
    for line in readlines(p)
        s = strip(line)
        (isempty(s) || startswith(s, '#')) && continue
        push!(hosts, s)
    end
    isempty(hosts) && throw(ArgumentError(explain_hosts_file_empty(p; surface = surface)))
    return hosts
end

"""SSH host names from a hosts file (`host:N` → `host` only; for setup / KitSession)."""
function read_hosts_file(
        path::AbstractString;
        surface::Symbol = :cli,
    )::Vector{String}
    return [split_worker_token(line)[1] for line in read_hosts_file_lines(path; surface = surface)]
end
