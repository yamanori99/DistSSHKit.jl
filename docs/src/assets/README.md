# Logo & social-preview assets

The three-circle mark (`#juliadot`, `#juliadot-lg`) is the Julia logo
(julia-circles), Copyright (c) 2012-2022 Stefan Karpinski,
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
DistSSHKit adapts it inside original machine / wire artwork.

- Design:
  [julia-logo-graphics](https://github.com/JuliaLang/julia-logo-graphics)
- Carve-out: [LICENSE](LICENSE)

Hand-edit sources and bake outputs that include those circles (logo, social,
diagram, PNG/GIF) are CC BY-NC-SA 4.0, not MIT.

Layout:

```text
assets/
  bake.jl, README.md, custom.css
  logo.svg          → logo/logo-dynamic.svg          (Documenter)
  logo-dark.svg     → logo/logo-dark-dynamic.svg     (Documenter)
  logo/             sources + logo rasters
  favicon.svg / favicon-dark.svg / favicon.ico   tab icon (parent, transparent)
  social/           social-preview SVGs + rasters
  diagram/          topology.svg (hand-edit) + dark SVG + PNG (bake)
```

Naming: **`static`** = end-state still; **`dynamic`** = SMIL / GIF motion.

## Matrix

- Logo light: dynamic `logo/logo-dynamic.svg`, `.gif`; static
  `logo/logo-static.svg`, `.png`
- Logo dark: dynamic `logo/logo-dark-dynamic.svg`; static
  `logo/logo-dark-static.svg`
- Social preview: dynamic `social/social-preview-dynamic.svg`, `.gif`;
  static `social/social-preview-static.svg`, `.png`

Derived dark SVGs prefix every `id` / `href="#…"` / `url(#…)` with `dark-`
so light and dark copies can sit in one HTML document.

GitHub README / README.ja use `<picture>` plus `prefers-color-scheme`
for the topology diagram and the footer logos
(`logo-static.svg` / `logo-dark-static.svg`). `img` / `srcset` are
`raw.githubusercontent.com/…/main/docs/src/assets/…` so JuliaHub can
load them. The light `img` is the fallback when `<picture>` is ignored.

Documenter discovers bare `logo.svg` / `logo-dark.svg` at this
directory's top level only.
`bake.jl` makes **symlinks** into `logo/` — do not edit the bare names.

## Hand-edit (sources)

| File | Role |
| --- | --- |
| `logo/logo-dynamic.svg` | Dynamic logo (SMIL) |
| `logo/logo-static.svg` | Static geometry (feeds static PNG + social-static) |
| `diagram/topology.svg` | English light diagram; bake writes dark SVG + PNG |
| `custom.css` | Sidebar logo; topology; restore `.docs-dark-only` |

## Bake (`bake.jl`, Julia only — no Python)

```bash
julia docs/src/assets/bake.jl              # SVGs + Documenter symlinks
julia docs/src/assets/bake.jl --png        # + PNG (rsvg or Chromium)
julia docs/src/assets/bake.jl --png --gif  # + GIF (Chromium + ffmpeg)
```

- default: Julia
- `--png`: `rsvg-convert` or Chrome; sizes: social 1280×640, logo 960×960,
  topology 1120×472, `favicon.ico` 16+32+48 from `favicon.svg`
- `--gif`: Chrome / Chromium (4 parallel workers) + `ffmpeg`

CI (`.github/workflows/assets-bake.yml`) re-runs the default bake when
`docs/src/assets/` changes and fails if SVG/symlink outputs drift, or if
PNG/GIF look older than their sources in git history (commit time of the
raster, or `.raster-stamp` from `--png` / `--gif`). Bake `--png` /
`--gif` locally before committing rasters (CI does not render them).

## Story (~8s, dynamic)

Setup → send → run → collect. Master is full-strength from t=0; remotes
start faint. Send: master spins (~3 turns), one color per turn (R→G→P);
remotes stay still until all solid. Then master + remotes spin together
(~3 turns). Collect: quiet data-dots return; master sparkles.
`prefers-reduced-motion` hides packets.

## Layout notes

- No ring; thin wires; size-aware fan; each remote owns its wire
- Social SVG and PNG **1280×640** (GitHub Social preview); fill most of a
  ~**960×480** zone (soft ≈100×60 inset); kit lockup (mark | title +
  tagline)
- Nested logo `viewBox="0 26 240 240"`; static/dynamic social share chrome
- Upload `social/social-preview-static.png` under GitHub → Settings →
  Social preview
