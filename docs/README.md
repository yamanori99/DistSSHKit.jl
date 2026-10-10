# Docs

Documenter site for DistSSHKit.jl. Sources live in `docs/src/`.

Layout:

- **Home** — `index.md`
- **First Steps** — `requirements.md`, then This machine (`tutorial/prepare.md`,
  `tutorial/demo.md`) and Always-on machine (`tutorial/queue-*.md`)
- **User Guide** — This machine (`manual/`), Julia version (`manual/up.md`),
  Always-on machine (`queue/`)
- **API** — `api.md`

Logos and social previews: see [`src/assets/README.md`](src/assets/README.md)
(`logo/` + `social/` + `diagram/`; edit `logo/logo-dynamic.svg` /
`logo/logo-static.svg` / `diagram/topology.svg`, then
`julia docs/src/assets/bake.jl`).

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Output: `docs/build/`. Use `--project=docs` (not the package root).
