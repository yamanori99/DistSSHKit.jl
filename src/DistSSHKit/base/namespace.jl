# Shared paths: project + `DISTRIBUTED_OUTPUT_DIR` + content-hash cache.
# Does not mount FUSE. Project rsync excludes `.distsshkit/`.

const _NS_CACHE_DIR = joinpath(".distsshkit", "cache", "sha256")

"""SHA-256 hex digest of file contents at `path`."""
function file_sha256(path::AbstractString)::String
    p = String(path)
    isfile(p) || throw(ArgumentError("file_sha256: not a file: $p"))
    return bytes2hex(open(SHA.sha256, p))
end

"""Project-relative cache path for digest `hash` (64 hex chars)."""
function cache_relpath(hash::AbstractString)::String
    h = lowercase(strip(String(hash)))
    length(h) == 64 && all(isxdigit, h) || throw(
        ArgumentError(
            "cache_relpath: expected 64 hex chars, got $(repr(hash))",
        )
    )
    return joinpath(_NS_CACHE_DIR, h)
end

"""Absolute cache path under `project` for `hash`."""
function cache_path(hash::AbstractString; project::AbstractString = pwd())::String
    return joinpath(canonical_local_path(project), cache_relpath(hash))
end

"""
    cache_file(src; project=pwd()) -> String

Copy `src` into `.distsshkit/cache/sha256/<digest>` if that blob is missing
or stale. Same contents share one file (no second copy). Returns the cache
path. Does not rsync by itself; `.distsshkit/` is excluded from project
sync.
"""
function cache_file(src::AbstractString; project::AbstractString = pwd())::String
    srcp = canonical_local_path(src)
    isfile(srcp) || throw(ArgumentError("cache_file: not a file: $srcp"))
    h = file_sha256(srcp)
    dest = cache_path(h; project = project)
    if isfile(dest)
        file_sha256(dest) == h && return dest
    end
    mkpath(dirname(dest))
    cp(srcp, dest; force = true)
    return dest
end

"""
    stored_path(rel; project=pwd(), output=nothing) -> String

Where `rel` is stored. `output=nothing` reads `DISTRIBUTED_OUTPUT_DIR`.
A passed string is used as given and does not read that variable.
`""` means no output directory.

An absolute `rel`, after expanding a leading `~` on this machine, is
returned as a canonical local path. The output directory is not consulted.

A relative `rel` uses the first match:

1. The output directory is set and `rel` already exists there.
2. `rel` already exists under `project`, even when the output directory is set.
3. The output directory is set, including when the file does not exist yet.
4. `project`, when the output directory is empty.
"""
function stored_path(
        rel::AbstractString;
        project::AbstractString = pwd(),
        output::Union{Nothing, AbstractString} = nothing,
    )::String
    r = String(rel)
    startswith(r, "~") && (r = expanduser(r))
    isabspath(r) && return canonical_local_path(r)
    proj = canonical_local_path(project)
    out = if output === nothing
        strip(get(ENV, "DISTRIBUTED_OUTPUT_DIR", ""))
    else
        strip(String(output))
    end
    cand_proj = joinpath(proj, r)
    if !isempty(out)
        cand_out = joinpath(canonical_local_path(out), r)
        ispath(cand_out) && return cand_out
        ispath(cand_proj) && return cand_proj
        return cand_out
    end
    return cand_proj
end
