using Test

# Regression: `go` may already have bound DistSSHKit names (including
# `cli_project_root`) before `setup.jl` is included. The setup `_using` guard
# must not key off `cli_project_root`, or `resolve_remote_project_root` never lands.

@testset "setup _using after cli_project_root" begin
    m = Module(:SetupUsingAfterCli)
    kit_src = abspath(joinpath(@__DIR__, "..", "..", "..", "..", "src"))
    setup_jl = joinpath(kit_src, "cli", "setup.jl")
    Core.eval(m, :(include(path) = Base.include($m, path)))
    Core.eval(m, :(const DistSSHKit = $(DistSSHKit)))
    Core.eval(m, quote
        using .DistSSHKit: cli_project_root
        const _cli_bound_before_setup = cli_project_root
    end)
    @test m._cli_bound_before_setup === DistSSHKit.cli_project_root
    Base.include(m, setup_jl)
    @test m.resolve_remote_project_root("/tmp/App.jl") isa AbstractString
    @test isdefined(m, :setup_main)
end
