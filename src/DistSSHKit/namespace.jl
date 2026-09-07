# Shared path namespace: project + `DISTRIBUTED_OUTPUT_DIR` + content-hash cache.
# Does not mount FUSE. Project rsync excludes `.distsshkit/`; `push_cache!` copies blobs.

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
sync. Use [`push_cache!`](@ref) to copy blobs to SSH hosts.
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
    ns_path(rel; project=pwd()) -> String

Resolve a namespace-relative path. Absolute `rel` is canonicalized.

Otherwise, if `DISTRIBUTED_OUTPUT_DIR` is set and that join exists, use it.
Else if the path exists under `project`, use that. Else if the output dir is
set, join there (typical write). Else join `project`.
"""
function ns_path(rel::AbstractString; project::AbstractString = pwd())::String
    r = String(rel)
    startswith(r, "~") && (r = expanduser(r))
    isabspath(r) && return canonical_local_path(r)
    proj = canonical_local_path(project)
    out = strip(get(ENV, "DISTRIBUTED_OUTPUT_DIR", ""))
    cand_proj = joinpath(proj, r)
    if !isempty(out)
        cand_out = joinpath(canonical_local_path(out), r)
        ispath(cand_out) && return cand_out
        ispath(cand_proj) && return cand_proj
        return cand_out
    end
    return cand_proj
end
