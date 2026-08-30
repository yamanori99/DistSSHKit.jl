using Documenter
using DistSSHKit

DocMeta.setdocmeta!(DistSSHKit, :DocTestSetup, :(using DistSSHKit); recursive=true)

makedocs(;
    modules=[DistSSHKit],
    authors="Takanori Yamamoto, Honoka Ampuku, and contributors",
    sitename="DistSSHKit.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        canonical="https://yamanori99.github.io/DistSSHKit.jl",
        edit_link="main",
        assets=[
            "assets/custom.css",
            # Same as Queue: Firefox uses the last rel=icon. ICO in <head> became
            # the Firefox fox. PNG last; ICO stays on disk at ./favicon.ico.
            Documenter.asset(
                "assets/favicon.svg";
                class=:ico,
                islocal=true,
                attributes=Dict(:type => "image/svg+xml"),
            ),
            Documenter.asset(
                "assets/favicon.png";
                class=:ico,
                islocal=true,
                attributes=Dict(:type => "image/png", :sizes => "32x32"),
            ),
            # Search Console (URL-prefix: https://yamanori99.github.io/DistSSHKit.jl/).
            RawHTMLHeadContent(
                """<meta name="google-site-verification" content="frfWUqaHuYYDmZzSSnBhfguS0Y5YC6zssij5qAot6ww" />""",
            ),
        ],
    ),
    pages=[
        "Introduction" => "index.md",
        "First Steps" => [
            "Requirements" => "requirements.md",
            "Prepare" => "tutorial/prepare.md",
            "Demo" => "tutorial/demo.md",
        ],
        "User Guide" => [
            "Overview" => "manual/index.md",
            "setup" => "manual/setup.md",
            "go" => "manual/go.md",
            "drive" => "manual/drive.md",
            "size" => "manual/size.md",
            "demo" => "manual/demo.md",
            "distsshkit" => "manual/distsshkit.md",
        ],
        "API" => "api.md",
    ],
    checkdocs=:none,
    warnonly=[:missing_docs, :docs_block, :cross_references],
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
    println("rewrote favicon type on $n HTML pages")
end

rewrite_favicon_types!(joinpath(@__DIR__, "build"))

deploydocs(;
    repo="github.com/yamanori99/DistSSHKit.jl.git",
    devbranch="main",
    push_preview=true,
    # stable = latest tagged release; appears after the first v* tag.
    versions=["stable" => "v^", "v#.#", "dev" => "dev"],
)
