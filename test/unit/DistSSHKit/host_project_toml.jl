using Test

@testset "host Project.toml" begin
    using TOML
    kit_root = _kit_root()
    kit_toml = joinpath(kit_root, "Project.toml")
    @test isfile(kit_toml)
    kit_deps = get(TOML.parsefile(kit_toml), "deps", Dict{String,String}())
    parent = dirname(kit_root)
    parent_proj = joinpath(parent, "Project.toml")
    nested_kit = joinpath(parent, "DistSSHKit", "Project.toml")
    # Monorepo: `.../App/DistSSHKit/test` → kit at `App/DistSSHKit`, host `App/Project.toml`.
    # Standalone kit repo: parent has no nested `DistSSHKit/Project.toml`; only assert kit deps exist.
    skip_merge_check = ["Distributed"]
    if isfile(parent_proj) && isfile(nested_kit) && abspath(kit_root) == abspath(joinpath(parent, "DistSSHKit"))
        root_deps = get(TOML.parsefile(parent_proj), "deps", Dict{String,String}())
        for (name, uuid) in kit_deps
            n = String(name)
            n in skip_merge_check && continue
            @test haskey(root_deps, n)
            @test root_deps[n] == String(uuid)
        end
    else
        @test haskey(kit_deps, "Distributed")
        @test haskey(kit_deps, "Pkg")
        @test haskey(kit_deps, "Dates")
        @test haskey(kit_deps, "TOML")
    end
end
