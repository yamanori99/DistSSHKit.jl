#!/usr/bin/env julia
#=
Regenerate DistSSHKit logo / social-preview derivatives.

Hand-edit sources:
  logo-dynamic.svg, logo-static.svg

Derived (names include static|dynamic):
  logo-dark-dynamic.svg, logo-dark-static.svg
  logo-static.png, logo-dynamic.gif
  social-preview-static.svg|.png
  social-preview-dynamic.svg|.gif

Documenter aliases (copies of *-dynamic.svg):
  logo.svg, logo-dark.svg

Default (SVG only): pure Julia, no extras.
Optional rasters: system CLIs only — rsvg-convert and/or Chromium, plus ffmpeg for GIF.
No Python.

  julia docs/src/assets/bake.jl
  julia docs/src/assets/bake.jl --png
  julia docs/src/assets/bake.jl --png --gif
=#

using Printf

const ROOT = @__DIR__

const SOCIAL_W, SOCIAL_H = 1280, 640
# Gentle lift only — 112/36 read high; 140/18.5 read low.
const LOGO_VIEWBOX = "0 26 240 240"
const MARK_X = 96
const MARK_SIZE = 360
const MARK_Y = 128
const TEXT_X, TEXT_Y = 520, SOCIAL_H ÷ 2
const FONT = "ui-sans-serif, system-ui, -apple-system, 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, sans-serif"

const STORY_S = 6.0
const DELAY_MS = 40
# Parallel Chrome workers for GIF frames (each frame is one headless launch).
const GIF_WORKERS = 4

die(msg) = (println(stderr, "error: ", msg); exit(1))

function readfile(name::AbstractString)
    p = joinpath(ROOT, name)
    isfile(p) || die("missing source $p")
    return read(p, String)
end

function writefile(name::AbstractString, text::AbstractString)
    p = joinpath(ROOT, name)
    write(p, text)
    println("wrote $name ($(sizeof(text)) bytes)")
end

to_dark(svg::AbstractString) =
    replace(
        replace(
            replace(svg, "stroke: #1a1d21;" => "stroke: #eef0f3;"),
            "fill: #1a1d21;" => "fill: #eef0f3;",
        ),
        "#a0a5ab" => "#7a8088",  # idle remote ring (light → dark surface)
    )

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
    src = kind == "static" ? "logo-static.svg" : "logo-dynamic.svg"
    return """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="$(SOCIAL_W)" height="$(SOCIAL_H)" viewBox="0 0 $(SOCIAL_W) $(SOCIAL_H)">
  <!-- social-preview-$(kind): shared chrome; nested mark from $(src); viewBox centers the fan -->
  <rect width="$(SOCIAL_W)" height="$(SOCIAL_H)" fill="#ffffff"/>
  <svg x="$(MARK_X)" y="$(MARK_Y)" width="$(MARK_SIZE)" height="$(MARK_SIZE)" viewBox="$(LOGO_VIEWBOX)">
$(inner)
  </svg>
  <text x="$(TEXT_X)" y="$(TEXT_Y)" dominant-baseline="middle" fill="#0f172a" font-family="$(FONT)" font-size="72" font-weight="800">DistSSHKit.jl</text>
</svg>
"""
end

html_wrap(body, w, h) = """<!DOCTYPE html><html><head><meta charset="utf-8"/>
<style>html,body{margin:0;width:$(w)px;height:$(h)px;overflow:hidden;background:#fff}</style>
<script>
window.__seek = function (t) {
  document.querySelectorAll("svg").forEach(function (s) {
    if (s.pauseAnimations) s.pauseAnimations();
    if (s.setCurrentTime) s.setCurrentTime(t);
  });
};
window.addEventListener("DOMContentLoaded", function () {
  var t = parseFloat(new URLSearchParams(location.search).get("t") || "0");
  if (!isNaN(t)) window.__seek(t);
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
    for name in ("logo.png", "logo.gif", "social-preview.svg", "social-preview.png", "social-preview.gif")
        p = joinpath(ROOT, name)
        if isfile(p)
            rm(p)
            println("removed legacy $name")
        end
    end
end

function bake_svgs!()
    logo = readfile("logo-dynamic.svg")
    logo_static = readfile("logo-static.svg")
    logo_dark = to_dark(logo)

    writefile("logo-dark-dynamic.svg", logo_dark)
    writefile("logo-dark-static.svg", to_dark(logo_static))
    writefile("logo.svg", logo)
    writefile("logo-dark.svg", logo_dark)

    social_static = build_social(logo_static, "static")
    social_dynamic = build_social(logo, "dynamic")
    writefile("social-preview-static.svg", social_static)
    writefile("social-preview-dynamic.svg", social_dynamic)

    return (; logo, logo_static, social_static, social_dynamic)
end

function rsvg_png(svg_path::AbstractString, out_path::AbstractString; width::Int, height::Int)
    candidates = String[]
    w = which_bin(("rsvg-convert",))
    w !== nothing && push!(candidates, w)
    for p in ("/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert")
        isfile(p) && push!(candidates, p)
    end
    isempty(candidates) && return false
    rsvg = first(candidates)
    try
        run(`$rsvg -w $width -h $height -o $out_path $svg_path`)
    catch
        return false
    end
    isfile(out_path) || return false
    println("wrote $(basename(out_path)) ($(filesize(out_path)) bytes) [rsvg-convert]")
    return true
end

function chrome_screenshot(html_path::AbstractString, out_png::AbstractString; w::Int, h::Int, t_s::Float64=0.0)
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
            "--force-device-scale-factor=1",
            "--window-size=$(w),$(h)",
            "--default-background-color=ffffffff",
            "--user-data-dir=$(udir)",
            "--virtual-time-budget=500",
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
            if proc !== nothing && !process_exited(proc)
                try
                    kill(proc, Base.SIGKILL)
                catch
                end
                timedwait(() -> process_exited(proc), 2.0)
            end
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

function bake_pngs!(arts)
    ok_any = false
    logo_static_path = joinpath(ROOT, "logo-static.svg")
    out_logo = joinpath(ROOT, "logo-static.png")
    if rsvg_png(logo_static_path, out_logo; width=480, height=480)
        ok_any = true
    else
        html = html_wrap(
            replace(strip_xml_decl(arts.logo_static), "width=\"240\" height=\"240\"" => "width=\"480\" height=\"480\"", count=1),
            480,
            480,
        )
        html_path = joinpath(tempdir(), "distsshkit-logo-static.html")
        write(html_path, html)
        if chrome_screenshot(html_path, out_logo; w=480, h=480)
            println("wrote logo-static.png ($(filesize(out_logo)) bytes) [chromium]")
            ok_any = true
        else
            println(stderr, "warn: skip logo-static.png (need rsvg-convert or Chromium)")
        end
    end

    out_social = joinpath(ROOT, "social-preview-static.png")
    html = html_wrap(arts.social_static, SOCIAL_W, SOCIAL_H)
    html_path = joinpath(tempdir(), "distsshkit-social-static.html")
    write(html_path, html)
    if chrome_screenshot(html_path, out_social; w=SOCIAL_W, h=SOCIAL_H)
        println("wrote social-preview-static.png ($(filesize(out_social)) bytes) [chromium]")
        ok_any = true
    elseif rsvg_png(joinpath(ROOT, "social-preview-static.svg"), out_social; width=SOCIAL_W, height=SOCIAL_H)
        ok_any = true
    else
        println(stderr, "warn: skip social-preview-static.png (need Chromium or rsvg-convert)")
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
    println("wrote $(basename(out_gif)) ($(filesize(out_gif)) bytes)")
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
end

function bake_gifs!(arts)
    logo_html = html_wrap(
        replace(strip_xml_decl(arts.logo), "width=\"240\" height=\"240\"" => "width=\"480\" height=\"480\"", count=1),
        480,
        480,
    )
    bake_gif_from_html!(logo_html, joinpath(ROOT, "logo-dynamic.gif"); w=480, h=480)

    social_html = html_wrap(arts.social_dynamic, SOCIAL_W, SOCIAL_H)
    bake_gif_from_html!(social_html, joinpath(ROOT, "social-preview-dynamic.gif"); w=SOCIAL_W, h=SOCIAL_H)
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
