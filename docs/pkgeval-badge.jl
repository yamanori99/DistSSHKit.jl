# Restyle one Nanosoldier PkgEval badge.
#
#   julia --startup-file=no docs/pkgeval-badge.jl PACKAGE docs/src/assets/pkgeval.svg
#
# Corners are square and the gloss gradient is removed. The status color
# stays whatever Nanosoldier drew (`passing`, `failed`, `skipped`, …).
# A missing badge does not write the destination and is not an error.

using Downloads

function refresh_pkgeval_badge(package::AbstractString, dest::AbstractString)::Bool
    url = "https://juliaci.github.io/NanosoldierReports/pkgeval_badges/$(first(package))/$(package).svg"
    svg = try
        String(take!(Downloads.download(url, IOBuffer(); timeout = 20)))
    catch e
        @warn "PkgEval badge not fetched" package url exception = e
        return false
    end
    if !occursin("PkgEval", svg)
        @warn "PkgEval badge missing" package url
        return false
    end
    svg = replace(svg, r"rx=\"\d+\"" => "rx=\"0\"")
    svg = replace(svg, r"<linearGradient[\s\S]*?</linearGradient>" => "")
    svg = replace(svg, r"<rect[^>]*fill=\"url\(#s\)\"[^>]*/>" => "")
    if isfile(dest) && read(dest, String) == svg
        return false
    end
    mkpath(dirname(abspath(dest)))
    write(dest, svg)
    return true
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: julia docs/pkgeval-badge.jl PACKAGE DEST.svg")
    refresh_pkgeval_badge(ARGS[1], ARGS[2])
end
