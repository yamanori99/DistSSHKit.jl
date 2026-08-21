# Host tokens & SSH failure summaries (drive / go / setup)

"""Whether `host` denotes this job's DistSSHKit parent in drive/go.

Prefer `masterhost`. Deprecated aliases `local` / `localhost` / `l` still
match and will be removed in DistSSHKit 0.4.

# Examples
```jldoctest
julia> using DistSSHKit

julia> DistSSHKit.is_local_host_name("masterhost")
true

julia> DistSSHKit.is_local_host_name("local")
true

julia> DistSSHKit.is_local_host_name("worker1")
false
```
"""
function is_local_host_name(host_name::AbstractString)::Bool
    h = String(host_name)
    return h == "masterhost" || h in ("localhost", "local", "l")
end

"""True for the deprecated relative names (`local` / `localhost` / `l`)."""
function is_deprecated_local_host_name(host_name::AbstractString)::Bool
    return String(host_name) in ("localhost", "local", "l")
end

const DEPRECATED_LOCAL_HOST_WARN =
    "`local` / `localhost` / `l` and `--local` / `-l` name this Julia process (relative) and will be removed in DistSSHKit 0.4. Use `masterhost` / `masterhost:N` for this job's DistSSHKit parent."

const _DEPRECATED_LOCAL_HOST_WARNED = Ref(false)

"""Reset the once-per-process deprecation flag (tests)."""
function _reset_deprecated_local_host_warning!()
    _DEPRECATED_LOCAL_HOST_WARNED[] = false
    return nothing
end

"""Warn once per process that relative `local` tokens/flags go away in 0.4."""
function warn_deprecated_local_host!()
    _DEPRECATED_LOCAL_HOST_WARNED[] && return nothing
    _DEPRECATED_LOCAL_HOST_WARNED[] = true
    @warn DEPRECATED_LOCAL_HOST_WARN
    return nothing
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
