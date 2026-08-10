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

## Story (~6s, dynamic)

**Setup → run → collect.** Local (master) dots stay full strength from t=0.
Remotes start faint. Run: three spin turns (ぐるん ×3); **one color per turn**
(R→G→P), solidifying on arrival. Setup: remotes float more (~7px peak) then
settle. Collect: one quiet data-dot returns per link; master sparkles.
`prefers-reduced-motion` hides packets.

## Layout notes

- No ring; thin solid wires; size-aware fan
- Each remote owns its wire (hub end inverse-tracks float)
- Social: **1280×640** (GitHub OG). **50px inset** (= 40pt on the 1024×512
  template). Kit lockup: mark beside a text column (name + tagline).
  Tagline leads with “A Julia kit for …”. Keep detail out of the outer margin.
- Nested logo `viewBox="0 26 240 240"` — small optical lift for the fan
- Static and dynamic social share the same chrome; only the nested logo differs
- Upload `social/social-preview-static.png` in GitHub → Settings → Social preview
  (SVG alone is not used for the repo card)
