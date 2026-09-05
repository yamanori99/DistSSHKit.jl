# Host tokens & SSH failure summaries (drive / go / setup)

"""Reserved token for this job's DistSSHKit parent (Kit side; not an SSH host)."""
const PARENT_HOST_NAME = "parent"

"""Prefix for an SSH child (`child:NAME` / `child:NAME:N`)."""
const CHILD_TOKEN_PREFIX = "child:"

"""Whether `host` denotes this job's DistSSHKit parent in drive/go/size.

Only `parent` matches. `parenthost` is rejected by `parse_placement_token`.
A token `local` / `localhost` / `l` is an ordinary SSH child (`child:local`).

# Examples
```jldoctest
julia> using DistSSHKit

julia> DistSSHKit.is_parent_host_name("parent")
true

julia> DistSSHKit.is_parent_host_name("parenthost")
false

julia> DistSSHKit.is_parent_host_name("local")
false

julia> DistSSHKit.is_parent_host_name("worker1")
false
```
"""
function is_parent_host_name(host_name::AbstractString)::Bool
    return String(host_name) == PARENT_HOST_NAME
end

"""`ArgumentError` for removed `--local` / `-l` (0.4)."""
function throw_removed_local_flag(arg::AbstractString)
    a = String(arg)
    throw(ArgumentError(
        "$(a) was removed in DistSSHKit 0.4; use $(PARENT_HOST_NAME) / $(PARENT_HOST_NAME):N",
    ))
end

function _placement_count_suffix(spec::AbstractString)::Tuple{String,Union{Nothing,Int}}
    s = strip(String(spec))
    if contains(s, ':')
        parts = split(s, ':'; limit=2)
        n = try
            parse(Int, parts[2])
        catch
            throw(ArgumentError("invalid count in $(repr(spec)); use NAME:N with integer N"))
        end
        return String(parts[1]), n
    end
    return s, nothing
end

"""Format a go/drive/size token (`parent[:N]` or `child:NAME[:N]`)."""
function format_placement_token(
    role::Symbol,
    name::String,
    n::Union{Nothing,Integer}=nothing,
)::String
    nn = n === nothing ? nothing : Int(n)
    if role === :parent
        nn === nothing && return PARENT_HOST_NAME
        return string(PARENT_HOST_NAME, ":", nn)
    elseif role === :child
        nn === nothing && return CHILD_TOKEN_PREFIX * name
        return string(CHILD_TOKEN_PREFIX, name, ":", nn)
    end
    throw(ArgumentError("format_placement_token: role must be :parent or :child, got $(repr(role))"))
end

format_placement_token(
    role::Symbol,
    name::AbstractString,
    n::Union{Nothing,Integer}=nothing,
) = format_placement_token(role, name isa String ? name : string(name), n)

const _PLACEMENT_HINT =
    "use `parent[:N]` or `child:NAME[:N]` (setup / size ignore `:N`)"

function throw_legacy_placement_token(raw::AbstractString)
    s = String(raw)
    base = split(s, ':'; limit=2)[1]
    if base == "parenthost" || base == "masterhost" || base == "childhost"
        throw(ArgumentError(
            "$(repr(s)) was removed; $_PLACEMENT_HINT",
        ))
    end
    return nothing
end

"""
Classify a go/drive/size placement token.

Returns `(role, name, n)` where `role` is `:parent` or `:child`, `name` is
`parent` or the SSH host, and `n` is the explicit count or `nothing` (`-w` / size).
"""
function parse_placement_token(
    spec::AbstractString,
)::NamedTuple{(:role, :name, :n), Tuple{Symbol, String, Union{Nothing, Int}}}
    s = strip(String(spec))
    isempty(s) && throw(ArgumentError("empty host token"))
    throw_legacy_placement_token(s)
    if s == PARENT_HOST_NAME
        return (role=:parent, name=PARENT_HOST_NAME, n=nothing)
    end
    if startswith(s, PARENT_HOST_NAME * ":")
        rest = s[(lastindex(PARENT_HOST_NAME) + 2):end]
        isempty(rest) && throw(ArgumentError("$(repr(s)): missing count after `parent:`"))
        n = try
            parse(Int, rest)
        catch
            throw(ArgumentError("$(repr(s)): parent count must be an integer"))
        end
        return (role=:parent, name=PARENT_HOST_NAME, n)
    end
    if startswith(s, CHILD_TOKEN_PREFIX)
        rest = s[(lastindex(CHILD_TOKEN_PREFIX) + 1):end]
        isempty(rest) && throw(ArgumentError("$(repr(s)): missing SSH name after `child:`"))
        name, n = _placement_count_suffix(rest)
        isempty(name) && throw(ArgumentError("$(repr(s)): missing SSH name after `child:`"))
        is_parent_host_name(name) && throw(ArgumentError(
            "$(repr(s)): Kit side is `parent`, not `child:parent`",
        ))
        return (role=:child, name=name, n)
    end
    throw(ArgumentError("$(repr(s)): $_PLACEMENT_HINT"))
end

"""True when a CLI token looks like a local `.jl` script path, not an SSH host.

# Examples
```jldoctest
julia> using DistSSHKit

julia> DistSSHKit.looks_like_script_host("job.jl")
true

julia> DistSSHKit.looks_like_script_host("host1")
false
```
"""
function looks_like_script_host(token::AbstractString)::Bool
    h = String(token)
    endswith(lowercase(h), ".jl") && return true
    return false
end

"""
True when a CLI token looks like a local filesystem path (not `user@host`).

Rejects path-like tokens so `setup --delete demos/foo.jl` fails early.

# Examples
```jldoctest
julia> using DistSSHKit

julia> DistSSHKit.looks_like_path_host("demos/foo.jl")
true

julia> DistSSHKit.looks_like_path_host("user@host")
false
```
"""
function looks_like_path_host(token::AbstractString)::Bool
    h = String(token)
    looks_like_script_host(h) && return true
    occursin('@', h) && return false
    (occursin('/', h) || occursin('\\', h)) && return true
    isfile(h) && return true
    return false
end

"""
Short, actionable summary for SSH / remote-shell failures.

Prefer this over dumping a full `ProcessFailedException` with a long `Cmd`.
"""
function summarize_ssh_error(err; stderr::AbstractString="")::String
    detail = strip(String(stderr))
    msg = sprint(showerror, err)
    blob = isempty(detail) ? msg : detail * "\n" * msg

    if occursin(r"(?i)bad configuration option:\s*usekeychain|usekeychain", blob)
        return "SSH config rejects UseKeychain (common with Homebrew OpenSSH). " *
               "Under `Host *` in ~/.ssh/config add `IgnoreUnknown UseKeychain`, " *
               "or put Apple's ssh first: PATH=\"/usr/bin:\$PATH\"."
    end
    if occursin(r"(?i)permission denied|no matching host key|host key verification failed", blob)
        return "SSH auth/host-key failed (BatchMode; no password prompt). " *
               "Fix: ssh-copy-id HOST  (or trust the host key once interactively)."
    end
    if occursin(r"(?i)could not resolve hostname|name or service not known|nodename nor servname", blob)
        return "SSH host not found (DNS / typo / missing SSH config Host alias)."
    end
    if occursin(r"(?i)connection timed out|operation timed out|connection refused", blob)
        return "SSH could not connect (timeout / refused). Check IP, VPN, and that the host is up."
    end
    if !isempty(detail)
        # First non-empty stderr line is usually the real OpenSSH message.
        for line in eachline(IOBuffer(detail))
            s = strip(line)
            isempty(s) && continue
            return _truncate_ssh_message(s)
        end
    end
    if occursin(r"ProcessExited\(255\)", msg) || occursin("[255]", msg)
        return "SSH failed (exit 255). Check: ssh -o BatchMode=yes -o ConnectTimeout=5 HOST echo ok"
    end
    return _truncate_ssh_message(msg)
end

function _truncate_ssh_message(msg::AbstractString; limit::Int=220)::String
    s = replace(strip(String(msg)), r"\s+" => " ")
    length(s) <= limit && return s
    return s[1:prevind(s, limit)] * "…"
end
