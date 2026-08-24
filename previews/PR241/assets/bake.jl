#!/usr/bin/env julia
#=
Regenerate DistSSHKit logo / social-preview / topology-diagram derivatives.

Hand-edit sources (under logo/ and diagram/):
  logo/logo-dynamic.svg, logo/logo-static.svg
  diagram/topology.svg

Derived:
  logo/logo-dark-*.svg, logo/logo-static.png, logo/logo-dynamic.gif
  social/social-preview-*.svg|.png|.gif
  diagram/topology-dark.svg
  diagram/topology.png

README.md, README.ja.md, and docs intro all use the English topology
(`parent` / `child 1…n`). Do not bake a Japanese-labelled copy.

Julia dots in these files are Copyright (c) 2012-2022 Stefan Karpinski,
CC BY-NC-SA 4.0 (https://github.com/JuliaLang/julia-logo-graphics), not MIT.
See LICENSE and docs/src/assets/README.md.

Documenter looks for assets/logo.svg and assets/logo-dark.svg; bake makes
**symlinks** to logo/logo-dynamic.svg and logo/logo-dark-dynamic.svg.

  julia docs/src/assets/bake.jl
  julia docs/src/assets/bake.jl --png
  julia docs/src/assets/bake.jl --png --gif
=#

using Printf

const ROOT = @__DIR__
const LOGO_DIR = "logo"
const SOCIAL_DIR = "social"
const DIAGRAM_DIR = "diagram"
const DIAGRAM_W, DIAGRAM_H = 560, 236
const DIAGRAM_PNG_W, DIAGRAM_PNG_H = DIAGRAM_W * 2, DIAGRAM_H * 2

# Light (source) → dark surface. Master stays a strong blue so it still reads as hub.
# Cluster/box fills sit above typical GitHub / Documenter dark chrome (#0d1117 / #1f2424).
const DIAGRAM_DARK = (
    ".box { fill: #ffffff; stroke: #475569;" =>
        ".box { fill: #334155; stroke: #cbd5e1;",
    ".link-more { fill: none; stroke: #cbd5e1;" =>
        ".link-more { fill: none; stroke: #64748b;",
    ".cluster { fill: #f8fafc; stroke: #cbd5e1;" =>
        ".cluster { fill: #1e293b; stroke: #94a3b8;",
    ".master { fill: #1e40af; stroke: #1e3a8a;" =>
        ".master { fill: #3b82f6; stroke: #93c5fd;",
    ".t { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; fill: #0f172a;" =>
        ".t { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; fill: #f8fafc;",
    ".t-sub { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; fill: #475569;" =>
        ".t-sub { font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; fill: #cbd5e1;",
    ".halo { fill: #f8fafc; }" => ".halo { fill: #1e293b; }",
)

const SOCIAL_W, SOCIAL_H = 1280, 640
# Gentle lift only — 112/36 read high; 140/18.5 read low.
const LOGO_VIEWBOX = "0 26 240 240"
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
const TAGLINE_1 = "A Julia kit for setup, execution, and result collection"
const TAGLINE_2 = "across local and SSH hosts."
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

const STORY_S = 8.0  # send (synced ぐるん) → joint spin → collect + hold
const DELAY_MS = 40
# Parallel Chrome workers for GIF frames (each frame is one headless launch).
const GIF_WORKERS = 4
# Static PNG supersample factor (render N× then downscale). Use 1 when exporting already-Retina sizes.
const PNG_SCALE = 2
# Deliverable PNG pixel sizes (Retina / 2× GitHub OG 1280×640).
const LOGO_PNG = 960
const SOCIAL_PNG_W, SOCIAL_PNG_H = SOCIAL_W * 2, SOCIAL_H * 2

die(msg) = (println(stderr, "error: ", msg); exit(1))

logo_path(name::AbstractString) = joinpath(LOGO_DIR, name)
social_path(name::AbstractString) = joinpath(SOCIAL_DIR, name)
diagram_path(name::AbstractString) = joinpath(DIAGRAM_DIR, name)

function topology_dark(svg::AbstractString)
    out = svg
    for (light, dark) in DIAGRAM_DARK
        out = replace(out, light => dark)
    end
    return prefix_svg_ids(out, "dark-")
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
    println("wrote $rel ($(sizeof(text)) bytes)")
end

"""Prefix `id=` / `href="#…"` / `url(#…)` so light+dark SVGs can share a DOM."""
function prefix_svg_ids(svg::AbstractString, prefix::AbstractString)
    ids = String[]
    for m in eachmatch(r"\bid=\"([^\"]+)\"", svg)
        push!(ids, String(m.captures[1]))
    end
    unique!(ids)
    sort!(ids; by=length, rev=true)
    out = svg
    for id in ids
        out = replace(out, "id=\"$(id)\"" => "id=\"$(prefix)$(id)\"")
        out = replace(out, "href=\"#$(id)\"" => "href=\"#$(prefix)$(id)\"")
        out = replace(out, "url(#$(id))" => "url(#$(prefix)$(id))")
    end
    return out
end

function to_dark(svg::AbstractString)
    dark = replace(svg, "stroke: #1a1d21;" => "stroke: #ffffff;")
    dark = replace(dark, "fill: #1a1d21;" => "fill: #ffffff;")
    dark = replace(dark, "stroke-width: 3.5;\n        stroke-linecap: round;\n        stroke-linejoin: round;" =>
        "stroke-width: 4;\n        stroke-linecap: round;\n        stroke-linejoin: round;")
    dark = replace(dark, ".link {\n        stroke: #ffffff;\n        stroke-width: 1.4;" =>
        ".link {\n        stroke: #ffffff;\n        stroke-width: 2;")
    dark = replace(dark, "#a0a5ab" => "#94a3b8")  # idle remote ring (legacy)
    return prefix_svg_ids(dark, "dark-")
end

function strip_xml_decl(svg::AbstractString)
    startswith(svg, "<?xml") || return svg
    i = findfirst("?>", svg)
    i === nothing && return svg
    return lstrip(svg[last(i)+1:end])
end

function svg_inner(svg::AbstractString)
    s = strip(strip_xml_decl(svg))
    m = match(r"^<svg[^>]*>([\s\S]*)</svg>\s*$", s)
    m === nothing && die("could not strip outer <svg>")
    return m.captures[1]
end

function build_social(logo_svg::AbstractString, kind::AbstractString)
    inner = svg_inner(logo_svg)
    src = kind == "static" ? logo_path("logo-static.svg") : logo_path("logo-dynamic.svg")
    return """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="$(SOCIAL_W)" height="$(SOCIAL_H)" viewBox="0 0 $(SOCIAL_W) $(SOCIAL_H)">
  <!-- social-preview-$(kind): 1280×640; safe $(SAFE_X)×$(SAFE_Y); mark | title lockup; from $(src) -->
  <rect width="$(SOCIAL_W)" height="$(SOCIAL_H)" fill="#ffffff"/>
  <svg x="$(MARK_X)" y="$(MARK_Y)" width="$(MARK_SIZE)" height="$(MARK_SIZE)" viewBox="$(LOGO_VIEWBOX)">
$(inner)
  </svg>
  <text x="$(TEXT_X)" y="$(TITLE_Y)" dominant-baseline="middle" fill="#0f172a" font-family="$(FONT)" font-size="$(TITLE_SIZE)" font-weight="800">$(TITLE)</text>
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
    )
        p = joinpath(ROOT, name)
        if isfile(p) || islink(p)
            rm(p)
            println("removed legacy $name")
        end
    end
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
    println("linked $link_name → $target_name")
end

function bake_svgs!()
    mkpath(joinpath(ROOT, LOGO_DIR))
    mkpath(joinpath(ROOT, SOCIAL_DIR))
    mkpath(joinpath(ROOT, DIAGRAM_DIR))

    logo = readfile(logo_path("logo-dynamic.svg"))
    logo_static = readfile(logo_path("logo-static.svg"))
    logo_dark = to_dark(logo)

    writefile(logo_path("logo-dark-dynamic.svg"), logo_dark)
    writefile(logo_path("logo-dark-static.svg"), to_dark(logo_static))
    # Documenter only discovers logo.svg / logo-dark.svg at assets/ root.
    ensure_symlink!("logo.svg", logo_path("logo-dynamic.svg"))
    ensure_symlink!("logo-dark.svg", logo_path("logo-dark-dynamic.svg"))

    social_static = build_social(logo_static, "static")
    social_dynamic = build_social(logo, "dynamic")
    writefile(social_path("social-preview-static.svg"), social_static)
    writefile(social_path("social-preview-dynamic.svg"), social_dynamic)

    topology = readfile(diagram_path("topology.svg"))
    topology_dark_svg = topology_dark(topology)
    writefile(diagram_path("topology-dark.svg"), topology_dark_svg)

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
    scale::Int=1,
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
    if downscale_png!(hi, out_path; w=width, h=height)
        println("wrote $(relpath(out_path, ROOT)) ($(filesize(out_path)) bytes) [rsvg-convert $(scale)×→1×]")
        return true
    end
    cp(hi, out_path; force=true)
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
            run(pipeline(`pkill -9 -f $marker`; stdout=devnull, stderr=devnull); wait=true)
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
    t_s::Float64=0.0,
    scale::Int=1,
)
    chrome = find_chrome()
    chrome === nothing && return false
    out_abs = abspath(out_png)
    html_uri = "file://" * abspath(html_path) * "?t=" * string(t_s)

    for attempt in 1:3
        isfile(out_abs) && rm(out_abs)
        udir = mktempdir(prefix="distsshkit-chrome-")
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
            proc = run(pipeline(Cmd(args); stdout=devnull, stderr=devnull); wait=false)
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
                rm(udir; recursive=true, force=true)
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
            run(pipeline(`$sips -z $h $w $src --out $dest`; stdout=devnull, stderr=devnull))
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
            run(pipeline(
                `$ffmpeg -y -i $src -vf scale=$(w):$(h):flags=lanczos $dest`;
                stdout=devnull,
                stderr=devnull,
            ))
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
    scale::Int=PNG_SCALE,
)
    out_path = joinpath(ROOT, out_rel)
    svg_path = joinpath(ROOT, svg_rel)
    if rsvg_png(svg_path, out_path; width=w, height=h, scale=scale)
        return true
    end

    html = html_wrap(html_body, w, h)
    html_path = joinpath(tempdir(), "distsshkit-$(replace(out_rel, "/" => "-")).html")
    write(html_path, html)
    if scale <= 1
        if chrome_screenshot(html_path, out_path; w=w, h=h, scale=1)
            println("wrote $out_rel ($(filesize(out_path)) bytes) [chromium]")
            return true
        end
        return false
    end

    hi = joinpath(tempdir(), "distsshkit-$(replace(out_rel, "/" => "-"))-$(scale)x.png")
    if !chrome_screenshot(html_path, hi; w=w, h=h, scale=scale)
        return false
    end
    if downscale_png!(hi, out_path; w=w, h=h)
        println("wrote $out_rel ($(filesize(out_path)) bytes) [chromium $(scale)×→1×]")
        return true
    end
    # Fallback: keep the hi-res shot if downscale tools are missing.
    cp(hi, out_path; force=true)
    println(stderr, "warn: kept $(scale)× PNG for $out_rel (no sips/ffmpeg downscale)")
    println("wrote $out_rel ($(filesize(out_path)) bytes) [chromium $(scale)×]")
    return true
end

function bake_pngs!(arts)
    ok_any = false
    logo_svg = logo_path("logo-static.svg")
    logo_png = logo_path("logo-static.png")
    logo_html_body = replace(
        strip_xml_decl(arts.logo_static),
        "width=\"240\" height=\"240\"" => "width=\"$(LOGO_PNG)\" height=\"$(LOGO_PNG)\"",
        count=1,
    )
    if bake_static_png!(logo_svg, logo_png, logo_html_body; w=LOGO_PNG, h=LOGO_PNG, scale=PNG_SCALE)
        ok_any = true
    else
        println(stderr, "warn: skip logo-static.png (need rsvg-convert or Chromium)")
    end

    social_svg = social_path("social-preview-static.svg")
    social_png = social_path("social-preview-static.png")
    # Export at 2× OG pixels; no further supersample (already Retina).
    social_html = replace(
        strip_xml_decl(arts.social_static),
        "width=\"$(SOCIAL_W)\" height=\"$(SOCIAL_H)\"" =>
            "width=\"$(SOCIAL_PNG_W)\" height=\"$(SOCIAL_PNG_H)\"",
        count=1,
    )
    if bake_static_png!(
        social_svg,
        social_png,
        social_html;
        w=SOCIAL_PNG_W,
        h=SOCIAL_PNG_H,
        scale=1,
    )
        ok_any = true
    else
        println(stderr, "warn: skip social-preview-static.png (need rsvg-convert or Chromium)")
    end

    for (svg_rel, png_rel, svg_text) in (
        (diagram_path("topology.svg"), diagram_path("topology.png"), arts.topology),
    )
        html_body = replace(
            strip_xml_decl(svg_text),
            "width=\"$(DIAGRAM_W)\" height=\"$(DIAGRAM_H)\"" =>
                "width=\"$(DIAGRAM_PNG_W)\" height=\"$(DIAGRAM_PNG_H)\"",
            count=1,
        )
        if bake_static_png!(
            svg_rel,
            png_rel,
            html_body;
            w=DIAGRAM_PNG_W,
            h=DIAGRAM_PNG_H,
            scale=1,
        )
            ok_any = true
        else
            println(stderr, "warn: skip $png_rel (need rsvg-convert or Chromium)")
        end
    end
    return ok_any
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
    run(pipeline(`$ffmpeg -y -framerate 25 -i $pattern -vf palettegen=max_colors=128:stats_mode=diff $palette`; stdout=devnull, stderr=devnull))
    run(pipeline(
        `$ffmpeg -y -framerate 25 -i $pattern -i $palette -lavfi paletteuse=dither=bayer:bayer_scale=3 -loop -1 $out_gif`;
        stdout=devnull,
        stderr=devnull,
    ))
    println("wrote $(relpath(out_gif, ROOT)) ($(filesize(out_gif)) bytes)")
end

function bake_gif_from_html!(html::AbstractString, out_gif::AbstractString; w::Int, h::Int)
    find_chrome() === nothing && die("Chromium/Chrome not found (required for --gif)")
    ffmpeg_ok = which_bin(("ffmpeg",)) !== nothing ||
        isfile("/opt/homebrew/bin/ffmpeg") || isfile("/usr/local/bin/ffmpeg")
    ffmpeg_ok || die("ffmpeg not found (required for --gif)")

    n = round(Int, STORY_S * 1000 / DELAY_MS)
    seq = mktempdir(prefix="distsshkit-gif-")
    html_path = joinpath(seq, "page.html")
    write(html_path, html)

    println("  capturing $n frames × $(GIF_WORKERS) Chrome workers…")
    t0 = time()
    done = Threads.Atomic{Int}(0)
    asyncmap(0:(n - 1); ntasks=GIF_WORKERS) do i
        t_s = i * DELAY_MS / 1000.0
        frame = joinpath(seq, @sprintf("f%04d.png", i))
        chrome_screenshot(html_path, frame; w=w, h=h, t_s=t_s) ||
            error("chromium screenshot failed at t=$(t_s)s")
        k = Threads.atomic_add!(done, 1) + 1
        if k == 1 || k % 25 == 0 || k == n
            println("  frame $k/$n")
        end
        return nothing
    end
    println("  captured $n frames in $(round(time() - t0; digits=1))s")
    ffmpeg_gif!(seq, out_gif)
    # Last-resort sweep if a worker crashed before finally ran.
    if Sys.isunix()
        try
            run(pipeline(`pkill -9 -f distsshkit-chrome-`; stdout=devnull, stderr=devnull); wait=true)
        catch
        end
    end
end

function bake_gifs!(arts)
    logo_html = html_wrap(
        replace(strip_xml_decl(arts.logo), "width=\"240\" height=\"240\"" => "width=\"480\" height=\"480\"", count=1),
        480,
        480,
    )
    bake_gif_from_html!(logo_html, joinpath(ROOT, logo_path("logo-dynamic.gif")); w=480, h=480)

    social_html = html_wrap(arts.social_dynamic, SOCIAL_W, SOCIAL_H)
    bake_gif_from_html!(social_html, joinpath(ROOT, social_path("social-preview-dynamic.gif")); w=SOCIAL_W, h=SOCIAL_H)
end

function main(args)
    do_png = "--png" in args
    do_gif = "--gif" in args

    println("baking SVGs…")
    arts = bake_svgs!()

    if do_png
        println("baking PNGs…")
        bake_pngs!(arts)
    end
    if do_gif
        println("baking GIFs (Chromium ×$(GIF_WORKERS) + ffmpeg)…")
        bake_gifs!(arts)
    end

    remove_legacy!()
    println("done")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
