# Where juliaup is. Channel add / update / default stays in setup.

"""Official install path for remote juliaup (non-interactive SSH has no login PATH)."""
const _JULIAUP_REMOTE_BIN_HOME = raw"$HOME/.juliaup/bin/juliaup"

"""
Ordered remote `juliaup` candidates (same preference as Julia binaries).

Prefers the official install under `\$HOME/.juliaup`, then Homebrew on macOS
(`/opt/homebrew`, `/usr/local`). Linux only needs the home install today.
"""
function remote_juliaup_candidates(uname_s::AbstractString)::Vector{String}
    os = lowercase(strip(String(uname_s)))
    home = _JULIAUP_REMOTE_BIN_HOME
    if startswith(os, "darwin")
        return String[home, "/opt/homebrew/bin/juliaup", "/usr/local/bin/juliaup"]
    end
    return String[home]
end

"""Candidates when remote OS is unknown: try home + Homebrew paths."""
function remote_juliaup_candidates()::Vector{String}
    return String[
        _JULIAUP_REMOTE_BIN_HOME,
        "/opt/homebrew/bin/juliaup",
        "/usr/local/bin/juliaup",
    ]
end

"""Shell word for a juliaup candidate (`\$HOME/...` expands on the remote)."""
function _juliaup_candidate_sh_word(path::AbstractString)::String
    p = String(path)
    p == _JULIAUP_REMOTE_BIN_HOME && return "\"\$HOME/.juliaup/bin/juliaup\""
    return p
end

"""Local juliaup candidates (same layout as remotes; expands `\$HOME`)."""
function local_juliaup_candidates()::Vector{String}
    test = strip(get(ENV, "DISTSSHKIT_TEST_LOCAL_JULIAUP", ""))
    isempty(test) || return String[test]
    home = joinpath(homedir(), ".juliaup", "bin", "juliaup")
    if Sys.isapple()
        return String[home, "/opt/homebrew/bin/juliaup", "/usr/local/bin/juliaup"]
    end
    return String[home]
end

"""First existing local juliaup path, or `nothing`."""
function find_local_juliaup(
        candidates::Vector{String} = local_juliaup_candidates(),
    )::Union{Nothing, String}
    for c in candidates
        p = String(c)
        isfile(p) && return p
    end
    return nothing
end

"""Julia binary beside a local juliaup (official / Homebrew shim layout)."""
function _local_julia_beside_juliaup(juliaup_path::AbstractString)::String
    return joinpath(dirname(String(juliaup_path)), "julia")
end
