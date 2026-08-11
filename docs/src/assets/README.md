# Logo & social-preview assets

Layout:

```text
assets/
  bake.jl, README.md, custom.css
  logo.svg          → logo/logo-dynamic.svg          (Documenter)
  logo-dark.svg     → logo/logo-dark-dynamic.svg     (Documenter)
  logo/             sources + logo rasters
  social/           social-preview SVGs + rasters
```

Naming: **`static`** = end-state still; **`dynamic`** = SMIL / GIF motion.

## Matrix

| | Dynamic | Static |
| --- | --- | --- |
| Logo light | `logo/logo-dynamic.svg`, `logo/logo-dynamic.gif` | `logo/logo-static.svg`, `logo/logo-static.png` |
| Logo dark | `logo/logo-dark-dynamic.svg` | `logo/logo-dark-static.svg` |
| Social preview | `social/social-preview-dynamic.svg`, `.gif` | `social/social-preview-static.svg`, `.png` |

Documenter discovers bare `logo.svg` / `logo-dark.svg` at this directory’s top level only.
`bake.jl` makes **symlinks** into `logo/` — do not edit the bare names.

## Hand-edit (sources)

| File | Role |
| --- | --- |
| `logo/logo-dynamic.svg` | Dynamic logo (SMIL) |
| `logo/logo-static.svg` | Static geometry (feeds static PNG + social-static) |
| `custom.css` | Sidebar logo size |

## Bake (`bake.jl`, Julia only — no Python)

```bash
julia docs/src/assets/bake.jl              # SVGs + Documenter symlinks
julia docs/src/assets/bake.jl --png        # + PNG (rsvg, or Chromium 2× then downscale)
julia docs/src/assets/bake.jl --png --gif  # + GIF (Chromium + ffmpeg)
```

| Mode | Needs |
| --- | --- |
| default | Julia |
| `--png` | `rsvg-convert` preferred, else Chrome; social PNG is 2560×1280 (2× OG), logo PNG is 960×960 |
| `--gif` | Chrome / Chromium (4 parallel workers) + `ffmpeg` |

CI (`.github/workflows/assets-bake.yml`) re-runs the default bake when `docs/src/assets/` changes and fails if SVG/symlink outputs drift. It **warns** (does not fail) if PNG/GIF look older than their sources in git history. Bake `--png` / `--gif` locally before committing rasters.

## Story (~8s, dynamic)

Setup → send → run → collect. Master is full-strength from t=0; remotes start faint.
Send: master spins (~3 turns), one color per turn (R→G→P); remotes stay still until all solid.
Then master + remotes spin together (~3 turns). Collect: quiet data-dots return; master sparkles.
`prefers-reduced-motion` hides packets.

## Layout notes

- No ring; thin wires; size-aware fan; each remote owns its wire
- Social SVG **1280×640**, PNG **2560×1280** (2×); fill most of a ~**960×480** zone (soft ≈100×60 inset); kit lockup (mark | title + tagline)
- Nested logo `viewBox="0 26 240 240"`; static/dynamic social share chrome
- Upload `social/social-preview-static.png` under GitHub → Settings → Social preview
