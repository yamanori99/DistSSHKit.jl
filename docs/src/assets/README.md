# Logo & social-preview assets

`bake.jl` writes the logo, favicon, social preview, and topology diagram.
The mark is an original fan. These files are MIT, with the rest of the package.

Layout:

```text
assets/
  bake.jl, README.md, custom.css
  logo.svg          → logo/logo-dynamic.svg          (Documenter)
  logo-dark.svg     → logo/logo-dark-dynamic.svg     (Documenter)
  logo/             logo SVGs + rasters
  favicon.svg / favicon-dark.svg / favicon.ico   tab icon (transparent)
  social/           social-preview SVGs + rasters
  diagram/          topology SVGs + PNG
```

Naming: **`static`** = end-state still; **`dynamic`** = SMIL / GIF motion.

## Matrix

- Logo light: dynamic `logo/logo-dynamic.svg`, `.gif`; static
  `logo/logo-static.svg`, `.png`
- Logo dark: dynamic `logo/logo-dark-dynamic.svg`; static
  `logo/logo-dark-static.svg`
- Social preview: dynamic `social/social-preview-dynamic.svg`, `.gif`;
  static `social/social-preview-static.svg`, `.png`
- README banner: static `social/readme-static.svg`, `.png` (white card)
  and `social/readme-dark-static.svg`, `.png` (transparent, light text)

If a dark SVG gains an `id`, prefix that `id` / `href="#…"` / `url(#…)`
with `dark-` so light and dark copies can sit in one HTML document.

GitHub README / README.ja put the README banner above the title, and
use `<picture>` plus `prefers-color-scheme` for that banner and for the
topology diagram. Paths are relative to the README, so GitHub shows the
files from the branch you are reading. An absolute `…/main/…` URL 404s
until those files are on main. The banner
is the social lockup with the vertical pad tightened (`README_PAD_Y`).
Its dark source is a transparent PNG. The light fallback is the white
card. The 1280×640 social preview stays the GitHub Settings upload.
Topology dark / light `source` are the transparent SVGs. The fallback
`img` is `topology.png`. JuliaHub strips or ignores `<picture>` /
`prefers-color-scheme`, so it shows the light fallback.

Documenter discovers bare `logo.svg` / `logo-dark.svg` at this
directory's top level only.
`bake.jl` makes **symlinks** into `logo/` — do not edit the bare names.

`custom.css` styles the sidebar logo and the topology figure.

## Bake (`bake.jl`, Julia only — no Python)

```bash
julia docs/src/assets/bake.jl              # SVGs + Documenter symlinks
julia docs/src/assets/bake.jl --png        # + PNG (rsvg or Chromium)
julia docs/src/assets/bake.jl --png --gif  # + GIF (Chromium + ffmpeg)
```

- default: Julia
- `--png`: `rsvg-convert` or Chrome; sizes: social 1280×640, README banner
  1280×420 (light and dark), logo 960×960, topology 1120×472,
  `favicon.ico` 16 (XS) + 32 (S) + 48 (M)
- `--gif`: Chrome / Chromium (4 parallel workers) + `ffmpeg`

CI (`.github/workflows/assets-bake.yml`) re-runs the default bake when
`docs/src/assets/` changes and fails if SVG/symlink outputs drift, or if
PNG/GIF look older than their sources in git history (commit time of the
raster, or `.raster-stamp-png` / `.raster-stamp-gif` after a complete
`--png` / `--gif`). Bake `--png` / `--gif` locally before committing
rasters (CI does not render them).

## Motion (5.2s)

The fan opens, a point travels to each child lamp, the lamps light, then
the fan closes.

## Layout notes

- Social SVG and PNG **1280×640** (GitHub Social preview); fill most of a
  ~**960×480** zone (soft ≈100×60 inset); kit lockup (mark | title +
  tagline)
- README banner **1280×420**: the same lockup, 40px above and below the
  mark. Light card is white. Dark card is transparent, with light text
- Nested logo `viewBox="0 0 128 128"`; static/dynamic social share chrome
- Upload `social/social-preview-static.png` under GitHub → Settings →
  Social preview
