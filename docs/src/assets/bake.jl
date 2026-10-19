#!/usr/bin/env julia
#=
Regenerate DistSSHKit logo / social-preview / topology-diagram derivatives.

`bake_svgs!` writes the logo, favicon, social preview, and topology SVGs.
PNG and GIF are `--png` / `--gif`.

README.md, README.ja.md, and docs intro all use the English topology
(`parent` / `child 1…n`). Do not bake a Japanese-labelled copy.

Documenter looks for assets/logo.svg and assets/logo-dark.svg; bake makes
**symlinks** to logo/logo-dynamic.svg and logo/logo-dark-dynamic.svg.

  julia docs/src/assets/bake.jl
  julia docs/src/assets/bake.jl --png
  julia docs/src/assets/bake.jl --png --gif
=#

using Dates
using Printf
using Zlib_jll

const ROOT = @__DIR__
const LOGO_DIR = "logo"
const SOCIAL_DIR = "social"
const DIAGRAM_DIR = "diagram"
const DIAGRAM_W, DIAGRAM_H = 560, 236
const DIAGRAM_PNG_W, DIAGRAM_PNG_H = DIAGRAM_W * 2, DIAGRAM_H * 2

const SOCIAL_W, SOCIAL_H = 1280, 640
const LOGO_VIEWBOX = "0 0 128 128"
# Keep content near the usual GitHub-oriented safe zone (~960×480), but fill it.
# Outer inset is a soft floor so edges are not flush to the crop.
const SAFE_X, SAFE_Y = 100, 60
# Kit lockup: mark beside a text column (title + tagline), column centered on mark.
const MARK_SIZE = 340
const MARK_GAP = 40
const TITLE = "DistSSHKit.jl"
const TEXT_W = 700  # approx. longest tagline line at tagline font size
const GROUP_W = MARK_SIZE + MARK_GAP + TEXT_W
const MARK_X = clamp((SOCIAL_W - GROUP_W) ÷ 2, SAFE_X, SOCIAL_W - SAFE_X - MARK_SIZE)
const TEXT_X = MARK_X + MARK_SIZE + MARK_GAP
const MARK_Y = clamp((SOCIAL_H - MARK_SIZE) ÷ 2, SAFE_Y, SOCIAL_H - SAFE_Y - MARK_SIZE)
const TAGLINE_1 = "A toolkit for running Julia computations"
const TAGLINE_2 = "across multiple machines over SSH."
# Vertically center title+taglines against the mark (not top-align).
const TEXT_BLOCK_H = 168
const TEXT_TOP = MARK_Y + (MARK_SIZE - TEXT_BLOCK_H) ÷ 2
const TITLE_Y = TEXT_TOP + 40
const TAGLINE_Y1 = TITLE_Y + 64
const TAGLINE_Y2 = TAGLINE_Y1 + 38
# Prefer concrete faces so rsvg/Pango (not just Chrome) can resolve them.
const FONT = "'Helvetica Neue', Helvetica, Arial, sans-serif"
const TITLE_SIZE = 76
const TAGLINE_SIZE = 28

const STORY_S = 5.2  # fan open, lamps, close
const DELAY_MS = 40
# Parallel Chrome workers for GIF frames (each frame is one headless launch).
const GIF_WORKERS = 4
# Static PNG supersample factor (render N× then downscale). Use 1 when exporting already-Retina sizes.
const PNG_SCALE = 2
# Deliverable PNG pixel sizes. Social is GitHub OG 1280×640 (Settings upload
# often rejects 2×). Sharpness comes from PNG_SCALE, not a larger deliverable.
const LOGO_PNG = 960
const SOCIAL_PNG_W, SOCIAL_PNG_H = SOCIAL_W, SOCIAL_H
# Browser tab icon. Transparent SVG/PNG; light + dark (Firefox uses media=).
const FAVICON = "favicon.ico"
const FAVICON_SVG = "favicon.svg"
const FAVICON_DARK_SVG = "favicon-dark.svg"
const FAVICON_PX = (16, 32, 48)

die(msg) = (println(stderr, "error: ", msg); exit(1))

logo_path(name::AbstractString) = joinpath(LOGO_DIR, name)
social_path(name::AbstractString) = joinpath(SOCIAL_DIR, name)
diagram_path(name::AbstractString) = joinpath(DIAGRAM_DIR, name)

"""PNG IHDR width/height, or `nothing` if the file is not a PNG."""
function png_ihdr_size(path::AbstractString)
    isfile(path) || return nothing
    return open(path, "r") do io
        sig = read(io, 8)
        sig == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] || return nothing
        ntoh(read(io, UInt32)) == 13 || return nothing
        String(read(io, 4)) == "IHDR" || return nothing
        w = Int(ntoh(read(io, UInt32)))
        h = Int(ntoh(read(io, UInt32)))
        return (w, h)
    end
end

function png_matches_size(path::AbstractString, w::Int, h::Int)
    return png_ihdr_size(path) == (w, h)
end

function be32(data::Vector{UInt8}, i::Int)
    return (UInt32(data[i]) << 24) | (UInt32(data[i + 1]) << 16) | (UInt32(data[i + 2]) << 8) | UInt32(data[i + 3])
end

function zlib_uncompress(src::Vector{UInt8})
    dest_cap = max(length(src) * 8, 4096)
    while dest_cap <= 8 * 1024 * 1024
        dest = Vector{UInt8}(undef, dest_cap)
        dest_len = Ref{Culong}(dest_cap)
        ret = @ccall Zlib_jll.libz.uncompress(
            dest::Ptr{UInt8},
            dest_len::Ptr{Culong},
            src::Ptr{UInt8},
            length(src)::Culong,
        )::Cint
        ret == 0 && return dest[1:Int(dest_len[])]
        ret == -5 || die("zlib uncompress failed: $ret")
        dest_cap *= 2
    end
    return die("zlib uncompress too large")
end

function png_paeth(a::UInt8, b::UInt8, c::UInt8)
    p = Int(a) + Int(b) - Int(c)
    pa, pb, pc = abs(p - Int(a)), abs(p - Int(b)), abs(p - Int(c))
    pa <= pb && pa <= pc && return a
    pb <= pc && return b
    return c
end

"""8-bit RGB/RGBA PNG → top-down RGBA bytes."""
function png_rgba8(path::AbstractString)
    data = read(path)
    data[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] || die("not a PNG: $path")
    i, w, h, bit_depth, color_type = 9, 0, 0, 0, 0
    idat = UInt8[]
    while i + 8 <= length(data)
        n = Int(be32(data, i))
        typ = String(data[(i + 4):(i + 7)])
        chunk = data[(i + 8):(i + 7 + n)]
        if typ == "IHDR"
            w = Int(be32(chunk, 1))
            h = Int(be32(chunk, 5))
            bit_depth = Int(chunk[9])
            color_type = Int(chunk[10])
            chunk[13] == 0x00 || die("interlaced PNG: $path")
        elseif typ == "IDAT"
            append!(idat, chunk)
        elseif typ == "IEND"
            break
        end
        i += 12 + n
    end
    bit_depth == 8 || die("favicon PNG is not 8-bit: $path")
    ch = color_type == 2 ? 3 : color_type == 6 ? 4 : die("favicon PNG color type $color_type: $path")
    raw = zlib_uncompress(idat)
    stride = w * ch
    length(raw) == h * (1 + stride) || die("PNG inflate size mismatch: $path")
    prev = zeros(UInt8, stride)
    out = Vector{UInt8}(undef, w * h * 4)
    o = 1
    for row in 1:h
        ft = raw[(row - 1) * (1 + stride) + 1]
        cur = raw[((row - 1) * (1 + stride) + 2):((row - 1) * (1 + stride) + 1 + stride)]
        recon = Vector{UInt8}(undef, stride)
        for x in 1:stride
            a = x > ch ? recon[x - ch] : 0x00
            b = prev[x]
            c = x > ch ? prev[x - ch] : 0x00
            v = cur[x]
            recon[x] = if ft == 0
                v
            elseif ft == 1
                v + a
            elseif ft == 2
                v + b
            elseif ft == 3
                v + UInt8((Int(a) + Int(b)) >> 1)
            elseif ft == 4
                v + png_paeth(a, b, c)
            else
                die("bad PNG filter $ft")
            end
        end
        for x in 1:w
            p = (x - 1) * ch
            out[o] = recon[p + 1]
            out[o + 1] = recon[p + 2]
            out[o + 2] = recon[p + 3]
            out[o + 3] = ch == 4 ? recon[p + 4] : 0xff
            o += 4
        end
        prev = recon
    end
    return w, h, out
end

function bmp_ico_image(sz::Int, rgba::Vector{UInt8})
    xor_nbytes = sz * sz * 4
    and_row = ((sz + 31) ÷ 32) * 4
    and_nbytes = and_row * sz
    buf = IOBuffer()
    write(buf, htol(UInt32(40)))
    write(buf, htol(Int32(sz)))
    write(buf, htol(Int32(2 * sz)))
    write(buf, htol(UInt16(1)))
    write(buf, htol(UInt16(32)))
    write(buf, htol(UInt32(0)))
    write(buf, htol(UInt32(xor_nbytes + and_nbytes)))
    write(buf, htol(UInt32(0)))
    write(buf, htol(UInt32(0)))
    write(buf, htol(UInt32(0)))
    write(buf, htol(UInt32(0)))
    for y in (sz - 1):-1:0
        for x in 0:(sz - 1)
            p = (y * sz + x) * 4 + 1
            write(buf, rgba[p + 2], rgba[p + 1], rgba[p], rgba[p + 3])
        end
    end
    write(buf, zeros(UInt8, and_nbytes))
    return take!(buf)
end

"""BMP-in-ICO so Firefox tabs actually draw the mark (PNG-in-ICO is often dropped)."""
function write_bmp_ico!(dest::AbstractString, pngs::Vector{Pair{Int, String}})
    payloads = Vector{Tuple{Int, Vector{UInt8}}}(undef, length(pngs))
    for (i, (sz, path)) in enumerate(pngs)
        png_matches_size(path, sz, sz) || die("favicon PNG is not $(sz)×$(sz): $path")
        w, h, rgba = png_rgba8(path)
        (w, h) == (sz, sz) || die("PNG decode size mismatch: $path")
        payloads[i] = (sz, bmp_ico_image(sz, rgba))
    end
    n = length(payloads)
    header = 6 + 16 * n
    open(dest, "w") do io
        write(io, htol(UInt16(0)))
        write(io, htol(UInt16(1)))
        write(io, htol(UInt16(n)))
        off = header
        for (sz, data) in payloads
            wbyte = sz >= 256 ? 0x00 : UInt8(sz)
            write(io, wbyte)
            write(io, wbyte)
            write(io, UInt8(0))
            write(io, UInt8(0))
            write(io, htol(UInt16(1)))
            write(io, htol(UInt16(32)))
            write(io, htol(UInt32(length(data))))
            write(io, htol(UInt32(off)))
            off += length(data)
        end
        for (_, data) in payloads
            write(io, data)
        end
    end
    return dest
end

const CARD = 70.0
const CARD_R = 13
const LAMP_C = (15.0, 15.0)
const PIVOT = (0.0, 70.0)
const ACCENT = "#9558b2"
const LOGO_DUR = "5.2s"
const OPEN_KT = "0;0.1;0.28;0.76;0.94;1"
const OPEN_KS = "0 0 1 1;.65 0 .25 1;0 0 1 1;.65 0 .25 1;0 0 1 1"
const LAMP_KT = "0;0.44;0.5;0.7;0.76;1"
const DOT_KT = "0;0.3;0.45;1"
const DOT_KS = "0 0 1 1;.45 0 .2 1;0 0 1 1"
const DOT_OP_KT = "0;0.299;0.3;0.45;0.49;1"

const LOGO_VARIANTS = Dict(
    :L => (angles = [-15, -30, -45], op = (0.27, 0.21), lamp = 4.5, child_lamps = true, edge = true),
    :M => (angles = [-15, -30, -45], op = (0.3, 0.24), lamp = 5.0, child_lamps = true, edge = true),
    :S => (angles = [-22, -44], op = (0.36, 0.28), lamp = 7.5, child_lamps = true, edge = false),
    :XS => (angles = [-30], op = (0.44, 0.34), lamp = 8.0, child_lamps = false, edge = false),
)

function num_str(x; digits::Int = 2)
    s = digits == 4 ? @sprintf("%.4f", x) : @sprintf("%.2f", x)
    s = rstrip(rstrip(s, '0'), '.')
    return s in ("", "-0") ? "0" : s
end

function rot_pt(p, angle; pivot = PIVOT)
    t = deg2rad(angle)
    dx, dy = p[1] - pivot[1], p[2] - pivot[2]
    return (
        pivot[1] + dx * cos(t) - dy * sin(t),
        pivot[2] + dx * sin(t) + dy * cos(t),
    )
end

function logo_placement(angles)
    pts = [rot_pt(p, a) for a in [0; angles] for p in ((0.0, 0.0), (CARD, 0.0), (CARD, CARD), (0.0, CARD))]
    xs = first.(pts)
    ys = last.(pts)
    x0, y0, x1, y1 = minimum(xs), minimum(ys), maximum(xs), maximum(ys)
    s = 108 / max(x1 - x0, y1 - y0)
    cx = 0.6 * (x0 + x1) / 2 + 0.4 * CARD / 2
    cy = 0.6 * (y0 + y1) / 2 + 0.4 * CARD / 2
    return round(s; digits = 4), round(64 - cx * s; digits = 2), round(64 - cy * s; digits = 2)
end

function logo_svg(; size::Symbol = :L, dark::Bool = false, animated::Bool = false)
    variant = LOGO_VARIANTS[size]
    s, tx, ty = logo_placement(variant.angles)
    op = dark ? variant.op[2] : variant.op[1]
    child_fill = dark ? "#c9a8e3" : ACCENT
    edge_color = dark ? "#d9c2ec" : ACCENT
    edge_op = dark ? 0.55 : 0.2
    edge_w = dark ? 1.2 : 0.6
    child_lamp = dark ? "#ead9f6" : ACCENT
    lr = variant.lamp
    lines = String[
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 128 128\">",
        "  <g transform=\"translate($(num_str(tx)) $(num_str(ty))) scale($(num_str(s; digits = 4)))\">",
    ]
    for angle in variant.angles
        edge = variant.edge ?
            " stroke=\"$edge_color\" stroke-opacity=\"$(num_str(edge_op))\" stroke-width=\"$(num_str(edge_w))\"" :
            ""
        if animated
            push!(lines, "    <g>")
            vals = "0 0 70;0 0 70;$angle 0 70;$angle 0 70;0 0 70;0 0 70"
            push!(
                lines,
                "      <animateTransform attributeName=\"transform\" type=\"rotate\" dur=\"$LOGO_DUR\" repeatCount=\"indefinite\" values=\"$vals\" keyTimes=\"$OPEN_KT\" calcMode=\"spline\" keySplines=\"$OPEN_KS\"/>",
            )
        else
            push!(lines, "    <g transform=\"rotate($angle 0 70)\">")
        end
        push!(
            lines,
            "      <rect x=\"0\" y=\"0\" width=\"$(Int(CARD))\" height=\"$(Int(CARD))\" rx=\"$CARD_R\" fill=\"$child_fill\" fill-opacity=\"$(num_str(op))\"$edge/>",
        )
        if variant.child_lamps
            if animated
                push!(
                    lines,
                    "      <circle cx=\"15\" cy=\"15\" r=\"$(num_str(lr))\" fill=\"$child_lamp\" opacity=\"0.18\"><animate attributeName=\"opacity\" dur=\"$LOGO_DUR\" repeatCount=\"indefinite\" values=\"0.18;0.18;1;1;0.18;0.18\" keyTimes=\"$LAMP_KT\"/></circle>",
                )
            else
                push!(lines, "      <circle cx=\"15\" cy=\"15\" r=\"$(num_str(lr))\" fill=\"$child_lamp\"/>")
            end
        end
        push!(lines, "    </g>")
    end
    push!(lines, "    <rect x=\"0\" y=\"0\" width=\"$(Int(CARD))\" height=\"$(Int(CARD))\" rx=\"$CARD_R\" fill=\"$ACCENT\"/>")
    push!(lines, "    <circle cx=\"15\" cy=\"15\" r=\"$(num_str(lr))\" fill=\"#ffffff\"/>")
    if animated && variant.child_lamps
        for angle in variant.angles
            x, y = rot_pt(LAMP_C, angle)
            dx, dy = x - LAMP_C[1], y - LAMP_C[2]
            push!(
                lines,
                "    <circle cx=\"15\" cy=\"15\" r=\"3\" fill=\"#ffffff\" opacity=\"0\"><animateMotion dur=\"$LOGO_DUR\" repeatCount=\"indefinite\" path=\"M0 0L$(num_str(dx)) $(num_str(dy))\" keyPoints=\"0;0;1;1\" keyTimes=\"$DOT_KT\" calcMode=\"spline\" keySplines=\"$DOT_KS\"/><animate attributeName=\"opacity\" dur=\"$LOGO_DUR\" repeatCount=\"indefinite\" values=\"0;0;1;1;0;0\" keyTimes=\"$DOT_OP_KT\"/></circle>",
            )
        end
    end
    push!(lines, "  </g>")
    push!(lines, "</svg>")
    return join(lines, "\n") * "\n"
end

function topology_text(x, y, label, fill; size = 13, weight = 400, anchor = "start")
    return "  <text x=\"$x\" y=\"$y\" font-family=\"$FONT\" font-size=\"$size\" font-weight=\"$weight\" fill=\"$fill\" text-anchor=\"$anchor\">$label</text>"
end

function topology_svg(; dark::Bool = false)
    ink = dark ? "#f5f7fa" : "#121419"
    sub = dark ? "#a3a9b0" : "#5b6068"
    mstroke = dark ? "#3a3542" : "#d9d2e2"
    pop = dark ? 0.16 : 0.06
    wfill = dark ? "#c9a8e3" : ACCENT
    wop = dark ? 0.18 : 0.16
    wstroke = dark ? "#d9c2ec" : ACCENT
    wsop = dark ? 0.45 : 0.3
    line = dark ? "#c9a8e3" : ACCENT
    lop = dark ? 0.6 : 0.55
    more = dark ? "#4a4552" : "#c9c3d1"
    lines = String["<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 560 236\" width=\"560\" height=\"236\">"]
    kids = [(24, "child 1"), (190, "child 2"), (380, "child n")]
    for (x, _) in kids
        push!(
            lines,
            "  <path d=\"M200 164 L$(x + 78) 100\" fill=\"none\" stroke=\"$line\" stroke-opacity=\"$lop\" stroke-width=\"1.5\" stroke-linecap=\"round\"/>",
        )
    end
    push!(
        lines,
        "  <path d=\"M200 164 L352 100\" fill=\"none\" stroke=\"$more\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-dasharray=\"3 4\"/>",
    )
    function chip(x, y, w, label)
        push!(
            lines,
            "  <rect x=\"$x\" y=\"$y\" width=\"$w\" height=\"36\" rx=\"8\" fill=\"$wfill\" fill-opacity=\"$wop\" stroke=\"$wstroke\" stroke-opacity=\"$wsop\" stroke-width=\"1\"/>",
        )
        push!(lines, topology_text(x + w / 2, y + 22.5, label, ink; anchor = "middle"))
        return nothing
    end
    for (x, name) in kids
        push!(
            lines,
            "  <rect x=\"$x\" y=\"22\" width=\"156\" height=\"78\" rx=\"12\" fill=\"none\" stroke=\"$mstroke\" stroke-width=\"1.5\"/>",
        )
        push!(lines, topology_text(x + 14, 44, name, ink; size = 14, weight = 600))
        chip(x + 10, 54, 136, "Worker × 1..n")
    end
    push!(lines, topology_text(358, 66, "…", sub; size = 20, anchor = "middle"))
    push!(
        lines,
        "  <rect x=\"124\" y=\"122\" width=\"312\" height=\"96\" rx=\"12\" fill=\"$ACCENT\" fill-opacity=\"$pop\" stroke=\"$mstroke\" stroke-width=\"1.5\"/>",
    )
    push!(lines, topology_text(138, 144, "parent", ink; size = 14, weight = 600))
    push!(lines, "  <rect x=\"140\" y=\"164\" width=\"120\" height=\"36\" rx=\"8\" fill=\"$ACCENT\"/>")
    push!(lines, topology_text(200, 187, "Master", "#ffffff"; size = 14, weight = 600, anchor = "middle"))
    chip(276, 164, 144, "Worker × 0..n")
    push!(lines, "</svg>")
    return join(lines, "\n") * "\n"
end

function readfile(rel::AbstractString)
    p = joinpath(ROOT, rel)
    isfile(p) || die("missing source $p")
    return read(p, String)
end

function writefile(rel::AbstractString, text::AbstractString)
    p = joinpath(ROOT, rel)
    mkpath(dirname(p))
    write(p, text)
    return println("wrote $rel ($(sizeof(text)) bytes)")
end

function strip_xml_decl(svg::AbstractString)
    startswith(svg, "<?xml") || return svg
    i = findfirst("?>", svg)
    i === nothing && return svg
    return lstrip(svg[(last(i) + 1):end])
end

function svg_inner(svg::AbstractString)
    s = strip(strip_xml_decl(svg))
    m = match(r"^<svg[^>]*>([\s\S]*)</svg>\s*$", s)
    m === nothing && die("could not strip outer <svg>")
    return m.captures[1]
end

function with_svg_size(svg::AbstractString, w::Int, h::Int)
    s = strip_xml_decl(svg)
    return replace(s, "<svg " => "<svg width=\"$w\" height=\"$h\" ", count = 1)
end

function build_social(logo_text::AbstractString, kind::AbstractString)
    inner = svg_inner(logo_text)
    src = kind == "static" ? logo_path("logo-static.svg") : logo_path("logo-dynamic.svg")
    return """<?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="$(SOCIAL_W)" height="$(SOCIAL_H)" viewBox="0 0 $(SOCIAL_W) $(SOCIAL_H)">
      <!-- social-preview-$(kind): 1280×640; safe $(SAFE_X)×$(SAFE_Y); mark | title lockup; from $(src) -->
      <rect width="$(SOCIAL_W)" height="$(SOCIAL_H)" fill="#ffffff"/>
      <svg x="$(MARK_X)" y="$(MARK_Y)" width="$(MARK_SIZE)" height="$(MARK_SIZE)" viewBox="$(LOGO_VIEWBOX)">
    $(inner)
      </svg>
      <text x="$(TEXT_X)" y="$(TITLE_Y)" dominant-baseline="middle" fill="#0f172a" font-family="$(FONT)" font-size="$(TITLE_SIZE)" font-weight="800">DistSSH<tspan fill="#9558b2">Kit</tspan>.jl</text>
      <text x="$(TEXT_X)" y="$(TAGLINE_Y1)" dominant-baseline="middle" fill="#475569" font-family="$(FONT)" font-size="$(TAGLINE_SIZE)" font-weight="500">$(TAGLINE_1)</text>
      <text x="$(TEXT_X)" y="$(TAGLINE_Y2)" dominant-baseline="middle" fill="#475569" font-family="$(FONT)" font-size="$(TAGLINE_SIZE)" font-weight="500">$(TAGLINE_2)</text>
    </svg>
    """
end

html_wrap(body, w, h) = """<!DOCTYPE html><html><head><meta charset="utf-8"/>
<style>html,body{margin:0;width:$(w)px;height:$(h)px;overflow:hidden;background:#fff}</style>
<script>
window.__seek = function (t) {
  document.querySelectorAll("svg").forEach(function (s) {
    // Seek then pause — pause-first can leave SMIL on a stale frame in headless Chrome.
    if (s.unpauseAnimations) s.unpauseAnimations();
    if (s.setCurrentTime) s.setCurrentTime(t);
    if (s.pauseAnimations) s.pauseAnimations();
  });
};
window.addEventListener("DOMContentLoaded", function () {
  var t = parseFloat(new URLSearchParams(location.search).get("t") || "0");
  if (!isNaN(t)) {
    // Double-seek after a tick so begin= / freeze states resolve reliably.
    window.__seek(t);
    requestAnimationFrame(function () { window.__seek(t); });
  }
});
</script>
</head><body>$(body)</body></html>
"""

function which_bin(names)
    for name in names
        path = Sys.which(name)
        path !== nothing && return path
    end
    return nothing
end

function find_chrome()
    mac = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    isfile(mac) && return mac
    mac_chr = "/Applications/Chromium.app/Contents/MacOS/Chromium"
    isfile(mac_chr) && return mac_chr
    return which_bin(("chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "chrome"))
end

function remove_legacy!()
    # Old flat layout leftovers at assets/ root.
    for name in (
            "logo.png",
            "logo.gif",
            "logo-dynamic.svg",
            "logo-static.svg",
            "logo-dark-dynamic.svg",
            "logo-dark-static.svg",
            "logo-static.png",
            "logo-dynamic.gif",
            "social-preview.svg",
            "social-preview.png",
            "social-preview.gif",
            "social-preview-static.svg",
            "social-preview-dynamic.svg",
            "social-preview-static.png",
            "social-preview-dynamic.gif",
            ".raster-stamp",
        )
        p = joinpath(ROOT, name)
        if isfile(p) || islink(p)
            rm(p)
            println("removed legacy $name")
        end
    end
    return
end

"""Relative symlink under ROOT; replaces an existing file or link."""
function ensure_symlink!(link_name::AbstractString, target_name::AbstractString)
    link_path = joinpath(ROOT, link_name)
    target_path = joinpath(ROOT, target_name)
    isfile(target_path) || die("symlink target missing: $target_name")
    if islink(link_path) || isfile(link_path) || isdir(link_path)
        rm(link_path)
    end
    cd(ROOT) do
        symlink(target_name, link_name)
    end
    return println("linked $link_name → $target_name")
end

"""`docs/src/favicon.*` so Firefox can fetch `./favicon.ico` next to `index.html`."""
function ensure_docroot_link!(name::AbstractString)
    srcroot = dirname(ROOT)
    target = joinpath("assets", name)
    isfile(joinpath(ROOT, name)) || return
    link = joinpath(srcroot, name)
    if islink(link) || isfile(link)
        rm(link)
    end
    cd(srcroot) do
        symlink(target, name)
    end
    return println("linked ../$name → $target")
end

function bake_svgs!()
    mkpath(joinpath(ROOT, LOGO_DIR))
    mkpath(joinpath(ROOT, SOCIAL_DIR))
    mkpath(joinpath(ROOT, DIAGRAM_DIR))

    logo = logo_svg(size = :L, dark = false, animated = true)
    logo_static = logo_svg(size = :L, dark = false, animated = false)
    writefile(logo_path("logo-dynamic.svg"), logo)
    writefile(logo_path("logo-static.svg"), logo_static)
    writefile(logo_path("logo-dark-dynamic.svg"), logo_svg(size = :L, dark = true, animated = true))
    writefile(logo_path("logo-dark-static.svg"), logo_svg(size = :L, dark = true, animated = false))
    # Documenter only discovers logo.svg / logo-dark.svg at assets/ root.
    ensure_symlink!("logo.svg", logo_path("logo-dynamic.svg"))
    ensure_symlink!("logo-dark.svg", logo_path("logo-dark-dynamic.svg"))

    social_static = build_social(logo_static, "static")
    social_dynamic = build_social(logo, "dynamic")
    writefile(social_path("social-preview-static.svg"), social_static)
    writefile(social_path("social-preview-dynamic.svg"), social_dynamic)

    topology = topology_svg(dark = false)
    topology_dark_svg = topology_svg(dark = true)
    writefile(diagram_path("topology.svg"), topology)
    writefile(diagram_path("topology-dark.svg"), topology_dark_svg)
    writefile(FAVICON_SVG, logo_svg(size = :S, dark = false))
    writefile(FAVICON_DARK_SVG, logo_svg(size = :S, dark = true))
    ensure_docroot_link!(FAVICON_SVG)
    ensure_docroot_link!(FAVICON_DARK_SVG)

    return (;
        logo,
        logo_static,
        social_static,
        social_dynamic,
        topology,
        topology_dark_svg,
    )
end

function rsvg_png(
        svg_path::AbstractString,
        out_path::AbstractString;
        width::Int,
        height::Int,
        scale::Int = 1,
        exact_size::Bool = false,
    )
    candidates = String[]
    w = which_bin(("rsvg-convert",))
    w !== nothing && push!(candidates, w)
    for p in ("/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert")
        isfile(p) && push!(candidates, p)
    end
    isempty(candidates) && return false
    rsvg = first(candidates)
    scale = max(1, scale)
    if scale == 1
        try
            run(`$rsvg -w $width -h $height -o $out_path $svg_path`)
        catch
            return false
        end
        isfile(out_path) || return false
        if exact_size && !png_matches_size(out_path, width, height)
            rm(out_path; force = true)
            println(stderr, "error: rsvg-convert wrote wrong size for $(relpath(out_path, ROOT)) (want $(width)×$(height))")
            return false
        end
        println("wrote $(relpath(out_path, ROOT)) ($(filesize(out_path)) bytes) [rsvg-convert]")
        return true
    end
    hi = joinpath(tempdir(), "distsshkit-rsvg-$(width)x$(height)-$(scale)x.png")
    try
        run(`$rsvg -w $(width * scale) -h $(height * scale) -o $hi $svg_path`)
    catch
        return false
    end
    (isfile(hi) && filesize(hi) > 0) || return false
    if downscale_png!(hi, out_path; w = width, h = height)
        if exact_size && !png_matches_size(out_path, width, height)
            rm(out_path; force = true)
            println(stderr, "error: downscale wrote wrong size for $(relpath(out_path, ROOT)) (want $(width)×$(height))")
            return false
        end
        println("wrote $(relpath(out_path, ROOT)) ($(filesize(out_path)) bytes) [rsvg-convert $(scale)×→1×]")
        return true
    end
    if exact_size
        println(stderr, "error: need sips or ffmpeg to downscale $(relpath(out_path, ROOT)) to $(width)×$(height)")
        return false
    end
    cp(hi, out_path; force = true)
    println(stderr, "warn: kept $(scale)× PNG for $(relpath(out_path, ROOT)) (no sips/ffmpeg downscale)")
    println("wrote $(relpath(out_path, ROOT)) ($(filesize(out_path)) bytes) [rsvg-convert $(scale)×]")
    return true
end

"""Kill a Chrome process and any helpers still bound to `user-data-dir`."""
function kill_chrome_session!(proc, udir::AbstractString)
    if proc !== nothing && !process_exited(proc)
        try
            kill(proc, Base.SIGKILL)
        catch
        end
        timedwait(() -> process_exited(proc), 2.0)
    end
    # Headless Chrome spawns Helpers; killing the parent alone often leaves them.
    # Match the unique temp profile path from this shot.
    marker = abspath(udir)
    if !isempty(marker) && isdir(marker) && Sys.isunix()
        try
            run(pipeline(`pkill -9 -f $marker`; stdout = devnull, stderr = devnull); wait = true)
        catch
        end
        sleep(0.05)
    end
    return nothing
end

function chrome_screenshot(
        html_path::AbstractString,
        out_png::AbstractString;
        w::Int,
        h::Int,
        t_s::Float64 = 0.0,
        scale::Int = 1,
    )
    chrome = find_chrome()
    chrome === nothing && return false
    out_abs = abspath(out_png)
    html_uri = "file://" * abspath(html_path) * "?t=" * string(t_s)

    for attempt in 1:3
        isfile(out_abs) && rm(out_abs)
        udir = mktempdir(prefix = "distsshkit-chrome-")
        args = String[
            chrome,
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            "--hide-scrollbars",
            "--force-device-scale-factor=$(scale)",
            "--window-size=$(w),$(h)",
            "--default-background-color=ffffffff",
            "--user-data-dir=$(udir)",
            "--virtual-time-budget=1500",
            "--screenshot=$(out_abs)",
            html_uri,
        ]
        proc = nothing
        try
            proc = run(pipeline(Cmd(args); stdout = devnull, stderr = devnull); wait = false)
            # Headless Chrome often writes the PNG then never exits; succeed on file, then kill.
            deadline = time() + 12.0
            while time() < deadline
                if isfile(out_abs) && filesize(out_abs) > 0
                    break
                end
                process_exited(proc) && break
                sleep(0.05)
            end
        catch
            # Chrome sometimes exits non-zero / signaled even after writing the shot.
        finally
            kill_chrome_session!(proc, udir)
            try
                rm(udir; recursive = true, force = true)
            catch
            end
        end
        if isfile(out_abs) && filesize(out_abs) > 0
            return true
        end
    end
    return false
end

"""Downscale PNG to exactly w×h (Lanczos via sips or ffmpeg)."""
function downscale_png!(src::AbstractString, dest::AbstractString; w::Int, h::Int)
    sips = which_bin(("sips",))
    if sips !== nothing
        try
            run(pipeline(`$sips -z $h $w $src --out $dest`; stdout = devnull, stderr = devnull))
            return isfile(dest) && filesize(dest) > 0
        catch
        end
    end
    ffmpeg = which_bin(("ffmpeg",))
    if ffmpeg === nothing
        for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg")
            isfile(p) && (ffmpeg = p; break)
        end
    end
    if ffmpeg !== nothing
        try
            run(
                pipeline(
                    `$ffmpeg -y -i $src -vf scale=$(w):$(h):flags=lanczos $dest`;
                    stdout = devnull,
                    stderr = devnull,
                )
            )
            return isfile(dest) && filesize(dest) > 0
        catch
        end
    end
    return false
end

"""Rasterize static SVG to PNG: prefer rsvg; else Chrome. Both can supersample via `scale`."""
function bake_static_png!(
        svg_rel::AbstractString,
        out_rel::AbstractString,
        html_body::AbstractString;
        w::Int,
        h::Int,
        scale::Int = PNG_SCALE,
        exact_size::Bool = false,
    )
    out_path = joinpath(ROOT, out_rel)
    svg_path = joinpath(ROOT, svg_rel)
    if rsvg_png(svg_path, out_path; width = w, height = h, scale = scale, exact_size = exact_size)
        return true
    end

    html = html_wrap(html_body, w, h)
    html_path = joinpath(tempdir(), "distsshkit-$(replace(out_rel, "/" => "-")).html")
    write(html_path, html)
    if scale <= 1
        if chrome_screenshot(html_path, out_path; w = w, h = h, scale = 1)
            if exact_size && !png_matches_size(out_path, w, h)
                rm(out_path; force = true)
                println(stderr, "error: chromium wrote wrong size for $out_rel (want $(w)×$(h))")
                return false
            end
            println("wrote $out_rel ($(filesize(out_path)) bytes) [chromium]")
            return true
        end
        return false
    end

    hi = joinpath(tempdir(), "distsshkit-$(replace(out_rel, "/" => "-"))-$(scale)x.png")
    if !chrome_screenshot(html_path, hi; w = w, h = h, scale = scale)
        return false
    end
    if downscale_png!(hi, out_path; w = w, h = h)
        if exact_size && !png_matches_size(out_path, w, h)
            rm(out_path; force = true)
            println(stderr, "error: downscale wrote wrong size for $out_rel (want $(w)×$(h))")
            return false
        end
        println("wrote $out_rel ($(filesize(out_path)) bytes) [chromium $(scale)×→1×]")
        return true
    end
    if exact_size
        println(stderr, "error: need sips or ffmpeg to downscale $out_rel to $(w)×$(h)")
        return false
    end
    # Fallback: keep the hi-res shot if downscale tools are missing.
    cp(hi, out_path; force = true)
    println(stderr, "warn: kept $(scale)× PNG for $out_rel (no sips/ffmpeg downscale)")
    println("wrote $out_rel ($(filesize(out_path)) bytes) [chromium $(scale)×]")
    return true
end

function write_raster_stamp!(name::AbstractString)
    path = joinpath(ROOT, name)
    write(path, string(Dates.now(Dates.UTC), "Z\n"))
    return println("wrote $name")
end

function bake_pngs!(arts)
    logo_svg = logo_path("logo-static.svg")
    logo_png = logo_path("logo-static.png")
    logo_html_body = with_svg_size(arts.logo_static, LOGO_PNG, LOGO_PNG)
    bake_static_png!(logo_svg, logo_png, logo_html_body; w = LOGO_PNG, h = LOGO_PNG, scale = PNG_SCALE) ||
        die("logo-static.png (need rsvg-convert or Chromium)")

    social_svg = social_path("social-preview-static.svg")
    social_png = social_path("social-preview-static.png")
    social_html = strip_xml_decl(arts.social_static)
    bake_static_png!(
        social_svg,
        social_png,
        social_html;
        w = SOCIAL_PNG_W,
        h = SOCIAL_PNG_H,
        scale = PNG_SCALE,
        exact_size = true,
    ) || die("social-preview-static.png (need rsvg-convert or Chromium, plus sips/ffmpeg to keep 1280×640)")

    bake_favicon!(arts) || die("$FAVICON (need rsvg-convert or Chromium)")

    for (svg_rel, png_rel, svg_text) in (
            (diagram_path("topology.svg"), diagram_path("topology.png"), arts.topology),
        )
        html_body = replace(
            strip_xml_decl(svg_text),
            "width=\"$(DIAGRAM_W)\" height=\"$(DIAGRAM_H)\"" =>
                "width=\"$(DIAGRAM_PNG_W)\" height=\"$(DIAGRAM_PNG_H)\"",
            count = 1,
        )
        bake_static_png!(
            svg_rel,
            png_rel,
            html_body;
            w = DIAGRAM_PNG_W,
            h = DIAGRAM_PNG_H,
            scale = 1,
        ) || die("$png_rel (need rsvg-convert or Chromium)")
    end
    return nothing
end

function bake_favicon!(_arts)
    ico_path = joinpath(ROOT, FAVICON)
    writefile(FAVICON_SVG, logo_svg(size = :S, dark = false))
    writefile(FAVICON_DARK_SVG, logo_svg(size = :S, dark = true))
    ensure_docroot_link!(FAVICON_SVG)
    ensure_docroot_link!(FAVICON_DARK_SVG)
    d = mktempdir(ROOT; prefix = ".favicon-")
    try
        function raster_mark(pngs, px, size::Symbol, dark::Bool)
            svg = joinpath(d, "$(dark ? "dark" : "light")-$px.svg")
            write(svg, logo_svg(size = size, dark = dark))
            src = joinpath(d, "$(dark ? "dark" : "light")-$px.png")
            body = with_svg_size(read(svg, String), px, px)
            if !bake_static_png!(
                    relpath(svg, ROOT),
                    relpath(src, ROOT),
                    body;
                    w = px,
                    h = px,
                    scale = PNG_SCALE,
                    exact_size = true,
                )
                return false
            end
            push!(pngs, px => src)
            return true
        end
        light = Pair{Int, String}[]
        dark = Pair{Int, String}[]
        for (px, size) in ((16, :XS), (32, :S), (48, :M))
            raster_mark(light, px, size, false) || return false
        end
        raster_mark(dark, 32, :S, true) || return false
        write_bmp_ico!(ico_path, light)
        png32 = joinpath(ROOT, "favicon.png")
        png32d = joinpath(ROOT, "favicon-dark.png")
        cp(first(p for p in light if p[1] == 32)[2], png32; force = true)
        cp(first(p for p in dark if p[1] == 32)[2], png32d; force = true)
        println("wrote $FAVICON ($(filesize(ico_path)) bytes)")
        println("wrote favicon.png ($(filesize(png32)) bytes)")
        println("wrote favicon-dark.png ($(filesize(png32d)) bytes)")
        ensure_docroot_link!(FAVICON)
        ensure_docroot_link!("favicon.png")
        ensure_docroot_link!("favicon-dark.png")
        return true
    finally
        rm(d; recursive = true, force = true)
    end
end

function ffmpeg_gif!(seq_dir::AbstractString, out_gif::AbstractString)
    candidates = String[]
    w = which_bin(("ffmpeg",))
    w !== nothing && push!(candidates, w)
    for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg")
        isfile(p) && push!(candidates, p)
    end
    isempty(candidates) && die("ffmpeg not found (required for --gif)")
    ffmpeg = first(candidates)
    palette = joinpath(tempdir(), "distsshkit-$(basename(out_gif))-pal.png")
    pattern = joinpath(seq_dir, "f%04d.png")
    run(pipeline(`$ffmpeg -y -framerate 25 -i $pattern -vf palettegen=max_colors=128:stats_mode=diff $palette`; stdout = devnull, stderr = devnull))
    run(
        pipeline(
            `$ffmpeg -y -framerate 25 -i $pattern -i $palette -lavfi paletteuse=dither=bayer:bayer_scale=3 -loop -1 $out_gif`;
            stdout = devnull,
            stderr = devnull,
        )
    )
    return println("wrote $(relpath(out_gif, ROOT)) ($(filesize(out_gif)) bytes)")
end

function bake_gif_from_html!(html::AbstractString, out_gif::AbstractString; w::Int, h::Int)
    find_chrome() === nothing && die("Chromium/Chrome not found (required for --gif)")
    ffmpeg_ok = which_bin(("ffmpeg",)) !== nothing ||
        isfile("/opt/homebrew/bin/ffmpeg") || isfile("/usr/local/bin/ffmpeg")
    ffmpeg_ok || die("ffmpeg not found (required for --gif)")

    n = round(Int, STORY_S * 1000 / DELAY_MS)
    seq = mktempdir(prefix = "distsshkit-gif-")
    html_path = joinpath(seq, "page.html")
    write(html_path, html)

    println("  capturing $n frames × $(GIF_WORKERS) Chrome workers…")
    t0 = time()
    done = Threads.Atomic{Int}(0)
    asyncmap(0:(n - 1); ntasks = GIF_WORKERS) do i
        t_s = i * DELAY_MS / 1000.0
        frame = joinpath(seq, @sprintf("f%04d.png", i))
        chrome_screenshot(html_path, frame; w = w, h = h, t_s = t_s) ||
            error("chromium screenshot failed at t=$(t_s)s")
        k = Threads.atomic_add!(done, 1) + 1
        if k == 1 || k % 25 == 0 || k == n
            println("  frame $k/$n")
        end
        return nothing
    end
    println("  captured $n frames in $(round(time() - t0; digits = 1))s")
    ffmpeg_gif!(seq, out_gif)
    # Last-resort sweep if a worker crashed before finally ran.
    return if Sys.isunix()
        try
            run(pipeline(`pkill -9 -f distsshkit-chrome-`; stdout = devnull, stderr = devnull); wait = true)
        catch
        end
    end
end

function bake_gifs!(arts)
    logo_html = html_wrap(
        with_svg_size(arts.logo, 480, 480),
        480,
        480,
    )
    bake_gif_from_html!(logo_html, joinpath(ROOT, logo_path("logo-dynamic.gif")); w = 480, h = 480)

    social_html = html_wrap(arts.social_dynamic, SOCIAL_W, SOCIAL_H)
    return bake_gif_from_html!(social_html, joinpath(ROOT, social_path("social-preview-dynamic.gif")); w = SOCIAL_W, h = SOCIAL_H)
end

function main(args)
    do_png = "--png" in args
    do_gif = "--gif" in args

    println("baking SVGs…")
    arts = bake_svgs!()

    if do_png
        println("baking PNGs…")
        bake_pngs!(arts)
        write_raster_stamp!(".raster-stamp-png")
    end
    if do_gif
        println("baking GIFs (Chromium ×$(GIF_WORKERS) + ffmpeg)…")
        bake_gifs!(arts)
        write_raster_stamp!(".raster-stamp-gif")
    end

    remove_legacy!()
    return println("done")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
