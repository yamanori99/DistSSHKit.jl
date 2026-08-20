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

deploydocs(;
    repo="github.com/yamanori99/DistSSHKit.jl.git",
    devbranch="main",
    push_preview=true,
    # stable = latest tagged release; appears after the first v* tag.
    versions=["stable" => "v^", "v#.#", "dev" => "dev"],
)
