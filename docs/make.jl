using Documenter
using DistSSHKit
using DistSSHQueue
using DistSSHRun
using Base64
using Pkg

include(joinpath(@__DIR__, "pkgeval-badge.jl"))

DocMeta.setdocmeta!(DistSSHKit, :DocTestSetup, :(using DistSSHKit); recursive = true)

refresh_pkgeval_badge("DistSSHKit", joinpath(@__DIR__, "src", "assets", "pkgeval.svg"))

const FAVICON_PNG_B64 = base64encode(read(joinpath(@__DIR__, "src", "assets", "favicon.png")))
const FAVICON_DARK_PNG_B64 = base64encode(read(joinpath(@__DIR__, "src", "assets", "favicon-dark.png")))

function _dep_git_rev(name::AbstractString)::String
    for dep in values(Pkg.dependencies())
        dep.name == name || continue
        rev = dep.git_revision
        rev === nothing && break
        return rev
    end
    return "main"
end

function _pkg_root(mod::Module)::String
    src = pathof(mod)
    src === nothing && error("$(nameof(mod)) has no source path")
    return dirname(dirname(src))
end

# Documenter 1.19 checks every module in `modules`. `checkdocs_ignored_modules`
# only skips submodules found while walking, so it does not drop DistSSHRun or
# DistSSHQueue when they are also in `modules`. They stay there: `@docs` keeps
# a docstring only when its defining module is in that list. This method drops
# them from the missing-docs set. Documenter 1.19's untyped `allbindings`
# walks each module and does not call this `Set{Module}` method, so the
# Vector call below is not recursive. `docs/Project.toml` allows 1.19.x only (`~1.19`).
# When upgrading Documenter, check whether this override is still required.
# If `checkdocs_ignored_modules` ignores a top-level module listed in `modules`, delete it.
function Documenter.allbindings(checkdocs::Symbol, mods::Set{Module})
    skip = Set{Module}([DistSSHRun, DistSSHQueue])
    kept = Module[m for m in mods if m ∉ skip]
    return Documenter.allbindings(checkdocs, kept)
end

# The docs build loads the released DistSSHRun, whose docstrings `@ref` names
# this manual cannot link. Kit and Run each define `host_tokens` and
# `cache_relpath`, so a `@ref` inside a Run docstring does not land on Kit's
# copy. These two stay until that duplication is gone.
const _DOC_REF_REWRITES = (
    "[`host_tokens`](@ref)" => "`host_tokens`",
    "[`cache_relpath`](@ref)" => "`cache_relpath`",
)

function _retarget_doc_refs!(mod::Module)
    for (_, multidoc) in Docs.meta(mod)
        multidoc isa Docs.MultiDoc || continue
        for docstr in values(multidoc.docs)
            text = docstr.text
            newtext = Any[part isa String ? replace(part, _DOC_REF_REWRITES...) : part for part in text]
            newtext == collect(Any, text) && continue
            docstr.text = Core.svec(newtext...)
        end
    end
    return nothing
end

_retarget_doc_refs!(DistSSHRun)

makedocs(;
    modules = [DistSSHKit, DistSSHRun, DistSSHQueue],
    remotes = Dict(
        _pkg_root(DistSSHRun) => (
            Remotes.GitHub("yamanori99", "DistSSHRun.jl"), _dep_git_rev("DistSSHRun"),
        ),
        _pkg_root(DistSSHQueue) => (
            Remotes.GitHub("yamanori99", "DistSSHQueue.jl"), _dep_git_rev("DistSSHQueue"),
        ),
    ),
    authors = "Takanori Yamamoto, Honoka Ampuku, and contributors",
    sitename = "DistSSHKit.jl",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://yamanori99.github.io/DistSSHKit.jl",
        edit_link = "main",
        # api.md is a large autogen page (Documenter default hard limit is 200 KiB).
        size_threshold_ignore = ["api.md"],
        assets = [
            "assets/custom.css",
            # Tab icon follows Documenter theme (`html.theme--*`), not OS scheme.
            RawHTMLHeadContent(
                """<link id="docs-favicon" rel="icon" type="image/png" sizes="32x32" href="data:image/png;base64,$(FAVICON_PNG_B64)" data-light="data:image/png;base64,$(FAVICON_PNG_B64)" data-dark="data:image/png;base64,$(FAVICON_DARK_PNG_B64)"/>""",
            ),
            "assets/favicon-theme.js",
            # Search Console (URL-prefix: https://yamanori99.github.io/DistSSHKit.jl/).
            RawHTMLHeadContent(
                """<meta name="google-site-verification" content="frfWUqaHuYYDmZzSSnBhfguS0Y5YC6zssij5qAot6ww" />""",
            ),
        ],
    ),
    pages = [
        "Home" => "index.md",
        "First Steps" => [
            "Requirements" => "requirements.md",
            "This machine" => [
                "Prepare" => "tutorial/prepare.md",
                "Demo" => "tutorial/demo.md",
            ],
            "Always-on machine" => [
                "Prepare the machine" => "tutorial/queue-prepare.md",
                "First job" => "tutorial/queue-client.md",
                "Walkthrough" => "tutorial/queue-walkthrough.md",
            ],
        ],
        "User Guide" => [
            "Overview" => "manual/index.md",
            "Prepare hosts" => [
                "setup" => "manual/setup.md",
                "up" => "manual/up.md",
            ],
            "This machine" => [
                "go" => "manual/go.md",
                "ride" => "manual/ride.md",
                "drive" => "manual/drive.md",
                "plan" => "manual/plan.md",
                "size" => "manual/size.md",
                "pool" => "manual/pool.md",
                "paths" => "manual/paths.md",
                "demo" => "manual/demo.md",
            ],
            "Always-on machine" => [
                "How it runs" => "queue/index.md",
                "Artifacts and paths" => "queue/artifacts.md",
                "submit" => "queue/submit.md",
                "status" => "queue/status.md",
                "fetch" => "queue/fetch.md",
                "hosts" => "queue/hosts.md",
                "serve" => "queue/serve.md",
                "qhost setup" => "queue/setup.md",
            ],
        ],
        "API" => "api.md",
    ],
    checkdocs = :exports,
)

# Documenter :ico always writes type=image/x-icon first. HTML5 keeps the first type,
# so Firefox treats the SVG/PNG as ICO, drops them, then looks for ./favicon.ico (404)
# and falls back to the sidebar logo.svg.
function rewrite_favicon_types!(build)
    rx_svg = r"""<link href="([^"]*favicon\.svg)" rel="icon" type="image/x-icon" type="image/svg\+xml"/>"""
    rx_png = r"""<link href="([^"]*favicon\.png)" rel="icon" type="image/x-icon" type="image/png" sizes="32x32"/>"""
    n = 0
    for (root, _, files) in walkdir(build)
        for f in files
            endswith(f, ".html") || continue
            path = joinpath(root, f)
            html = read(path, String)
            html2 = replace(
                html,
                rx_svg => s"""<link href="\1" rel="icon" type="image/svg+xml"/>""",
            )
            html2 = replace(
                html2,
                rx_png => s"""<link href="\1" rel="icon" type="image/png" sizes="32x32"/>""",
            )
            if html2 != html
                write(path, html2)
                n += 1
            end
        end
    end
    return println("rewrote favicon type on $n HTML pages")
end

rewrite_favicon_types!(joinpath(@__DIR__, "build"))

deploydocs(;
    repo = "github.com/yamanori99/DistSSHKit.jl.git",
    devbranch = "main",
    push_preview = true,
    # stable = latest tagged release; appears after the first v* tag.
    versions = ["stable" => "v^", "v#.#", "dev" => "dev"],
)
