# Logo & social-preview assets

Naming: **`static`** = end-state still; **`dynamic`** = SMIL / GIF motion.

## Matrix

| | Dynamic | Static |
| --- | --- | --- |
| Logo light | `logo-dynamic.svg`, `logo-dynamic.gif` | `logo-static.svg`, `logo-static.png` |
| Logo dark | `logo-dark-dynamic.svg` | `logo-dark-static.svg` |
| Social preview | `social-preview-dynamic.svg`, `social-preview-dynamic.gif` | `social-preview-static.svg`, `social-preview-static.png` |

Documenter also needs bare `logo.svg` / `logo-dark.svg`. `bake.jl` writes them as
**copies of the `*-dynamic.svg` files** — do not edit the bare names.

## Hand-edit (sources)

| File | Role |
| --- | --- |
| `logo-dynamic.svg` | Dynamic logo (SMIL) |
| `logo-static.svg` | Static geometry (feeds static PNG + social-static) |
| `custom.css` | Sidebar logo size |

## Bake (`bake.jl`, Julia only — no Python)

```bash
julia docs/src/assets/bake.jl              # SVGs + Documenter aliases
julia docs/src/assets/bake.jl --png        # + PNG (rsvg-convert and/or Chromium)
julia docs/src/assets/bake.jl --png --gif  # + GIF (Chromium + ffmpeg)
```

| Mode | Needs |
| --- | --- |
| default | Julia |
| `--png` | `rsvg-convert` (librsvg) and/or Google Chrome / Chromium |
| `--gif` | Chrome / Chromium (4 parallel workers) + `ffmpeg` |

## Story (~6s, dynamic)

Remotes start with hollow gray rings. Master sends R→G→P; rings fill to
solid official juliacircles (R, r=0.75R). Master and remotes spin together
(same window). One quiet data-dot returns per link; master sparkles on
receive. Remotes float then settle. `prefers-reduced-motion` hides packets.

## Layout notes

- No ring; thin solid wires; size-aware fan
- Each remote owns its wire (hub end inverse-tracks float)
- Social chrome: mark `(96, 128)` size 360; title `(520, 320)`
- Nested logo `viewBox="0 26 240 240"` — small optical lift for the fan
- Static and dynamic social share the same chrome; only the nested logo differs
