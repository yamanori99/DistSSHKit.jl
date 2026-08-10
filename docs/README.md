# Docs

Documenter site for DistSSHKit.jl. Sources live in `docs/src/`.

Layout (same idea as [DataFrames.jl](https://dataframes.juliadata.org/stable/)):

- **Introduction** — `index.md`
- **First Steps** — `requirements.md`, `tutorial/`
- **User Guide** — `manual/`
- **API** — `api.md`

Logos and social previews: see [`src/assets/README.md`](src/assets/README.md)
(`logo/` + `social/`; edit `logo/logo-dynamic.svg` / `logo/logo-static.svg`, then
`julia docs/src/assets/bake.jl`).

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Output: `docs/build/`. Use `--project=docs` (not the package root).
