"""Compare two Julia versions and classify the difference:
`:none` (equal), `:minor` (major.minor differs), or `:patch` (patch only)."""
function julia_version_mismatch_kind(
        local_version::VersionNumber,
        remote_version::VersionNumber,
    )::Symbol
    if remote_version.major != local_version.major || remote_version.minor != local_version.minor
        return :minor
    elseif remote_version.patch != local_version.patch
        return :patch
    end
    return :none
end

"""Oldest `juliaup --version` this package will run. Older builds are an error."""
const JULIAUP_MIN = v"1.22.0"

"""`Juliaup x.y.z` from `juliaup --version`, or `nothing`."""
function _juliaup_version(text::AbstractString)::Union{Nothing, VersionNumber}
    line = ""
    for row in eachsplit(String(text), '\n'; keepempty = false)
        line = strip(row)
        isempty(line) || break
    end
    m = match(r"^Juliaup\s+(\d+\.\d+(?:\.\d+)?)\b", line)
    m === nothing && return nothing
    cap = m.captures[1]
    cap === nothing && return nothing
    return VersionNumber(String(cap))
end

"""Error when `ver` is missing or older than [`JULIAUP_MIN`](@ref)."""
function _reject_old_juliaup(ver::Union{Nothing, VersionNumber}, seen::AbstractString)
    if ver === nothing
        line = ""
        for row in eachsplit(String(seen), '\n'; keepempty = false)
            line = strip(row)
            isempty(line) || break
        end
        shown = isempty(line) ? "empty" : line
        error("juliaup --version unreadable: $shown")
    end
    floor = "$(JULIAUP_MIN.major).$(JULIAUP_MIN.minor)"
    ver < JULIAUP_MIN && error("juliaup $ver is older than $floor")
    return nothing
end

"""Channel string for juliaup from a Julia `VersionNumber` (`\"1.13\"`)."""
juliaup_channel(v::VersionNumber = VERSION)::String = "$(v.major).$(v.minor)"

"""True when `remote` is the same major.minor as `local` but a newer version."""
function juliaup_parent_behind_channel(
        local_version::VersionNumber,
        remote_version::VersionNumber,
    )::Bool
    julia_version_mismatch_kind(local_version, remote_version) == :minor && return false
    return remote_version > local_version
end
