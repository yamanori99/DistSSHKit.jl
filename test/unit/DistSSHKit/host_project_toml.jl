using Test
using TOML

@testset "host Project.toml" begin
    kit_root = _kit_root()
    kit_toml = joinpath(kit_root, "Project.toml")
    @test isfile(kit_toml)
    kit = TOML.parsefile(kit_toml)
    kit_deps = kit["deps"]::AbstractDict
    parent = dirname(kit_root)
    parent_proj = joinpath(parent, "Project.toml")
    nested_kit = joinpath(parent, "DistSSHKit", "Project.toml")
    # Monorepo: `.../App/DistSSHKit/test` → kit at `App/DistSSHKit`, host `App/Project.toml`.
    # Standalone kit repo: parent has no nested `DistSSHKit/Project.toml`; only assert kit deps exist.
    in_host_tree =
        isfile(parent_proj) &&
        isfile(nested_kit) &&
        abspath(kit_root) == abspath(joinpath(parent, "DistSSHKit"))
    if in_host_tree
        root_deps = TOML.parsefile(parent_proj)["deps"]::AbstractDict
        for (name, uuid) in kit_deps
            n = String(name)
            if n == "Distributed"
                continue
            end
            @test haskey(root_deps, n)
            @test root_deps[n] == String(uuid)
        end
    else
        @test haskey(kit_deps, "Distributed")
        @test haskey(kit_deps, "Pkg")
        @test haskey(kit_deps, "Dates")
        @test haskey(kit_deps, "TOML")
    end
    @test haskey(kit, "apps")
    apps = kit["apps"]::AbstractDict
    @test haskey(apps, "distsshkit")
    @test !haskey(apps, "DistSSHKit")
    @test !haskey(apps, "dsk")
    flags = apps["distsshkit"]["julia_flags"]::AbstractVector
    @test "--startup-file=no" in String.(flags)
end
