using Test
using TOML

@testset "host Project.toml" begin
    kit_root = _kit_root()
    kit_toml = joinpath(kit_root, "Project.toml")
    @test isfile(kit_toml)
    kit = TOML.parsefile(kit_toml)
    kit_deps = Dict{String,String}()
    for (k, v) in kit["deps"]
        kit_deps[String(k)] = String(v)
    end
    parent = dirname(kit_root)
    parent_proj = joinpath(parent, "Project.toml")
    nested_kit = joinpath(parent, "DistSSHKit", "Project.toml")
    # Monorepo: `.../App/DistSSHKit/test` → kit at `App/DistSSHKit`, host `App/Project.toml`.
    # Standalone kit repo: parent has no nested `DistSSHKit/Project.toml`; only assert kit deps exist.
    skip_merge_check = ["Distributed"]
    if isfile(parent_proj) && isfile(nested_kit) && abspath(kit_root) == abspath(joinpath(parent, "DistSSHKit"))
        root_deps = Dict{String,String}()
        for (k, v) in TOML.parsefile(parent_proj)["deps"]
            root_deps[String(k)] = String(v)
        end
        for (n, uuid) in kit_deps
            n in skip_merge_check && continue
            @test haskey(root_deps, n)
            @test root_deps[n] == uuid
        end
    else
        @test haskey(kit_deps, "Distributed")
        @test haskey(kit_deps, "Pkg")
        @test haskey(kit_deps, "Dates")
        @test haskey(kit_deps, "TOML")
    end
    apps = get(kit, "apps", nothing)
    @test apps isa AbstractDict
    @test haskey(apps, "distsshkit")
    @test !haskey(apps, "DistSSHKit")
    @test !haskey(apps, "dsk")
    flags = get(apps["distsshkit"], "julia_flags", nothing)
    @test flags isa AbstractVector
    @test "--startup-file=no" in String.(flags)
end
