#!/usr/bin/env julia
# DistSSHKit unit tests (optional; not required in every host application).
# From the application repo root (when this tree lives under `DistSSHKit/`):
#   julia --project=. DistSSHKit/test/runtests.jl
# From a standalone kit checkout (this directory as the active project):
#   julia --project=. -e 'using Pkg; Pkg.test()'
#   julia --project=. test/runtests.jl
#
# Maintainer checks: CONTRIBUTING.md ("Before opening a PR").
#   jetls --threads=auto -- check ... demos/with_kit/*.jl demos/without_kit/*.jl ...

using Test

isdefined(@__MODULE__, :DistSSHKit) || include(joinpath(@__DIR__, "..", "src", "DistSSHKit.jl"))
using .DistSSHKit

include(joinpath(@__DIR__, "support.jl"))

# Runs first, and separately from unit/integration batches: unlike those files (which
# reuse the `Main.DistSSHKit` module loaded above via relative `include`), `aqua.jl`
# needs `using DistSSHKit` to resolve to a real, top-level package module (see comment
# in that file).
println("▸ aqua.jl")
include(joinpath(@__DIR__, "aqua.jl"))

function _unit_test_files()
    return (
        joinpath("DistSSHKit", "display.jl"),
        joinpath("DistSSHKit", "explain.jl"),
        joinpath("DistSSHKit", "remote.jl"),
        joinpath("DistSSHKit", "distributed.jl"),
        joinpath("DistSSHKit", "drive.jl"),
        joinpath("DistSSHKit", "size.jl"),
        joinpath("DistSSHKit", "go.jl"),
        joinpath("DistSSHKit", "module.jl"),
        joinpath("DistSSHKit", "cli", "args.jl"),
        joinpath("DistSSHKit", "cli", "session.jl"),
        joinpath("DistSSHKit", "hosts.jl"),
        joinpath("DistSSHKit", "main_dispatch.jl"),
        joinpath("DistSSHKit", "demo_cli.jl"),
        joinpath("DistSSHKit", "host_project_toml.jl"),
        joinpath("DistSSHKit", "setup_api.jl"),
        joinpath("DistSSHKit", "setup", "checks.jl"),
        joinpath("DistSSHKit", "setup", "hosts.jl"),
        joinpath("DistSSHKit", "setup", "rsync.jl"),
        joinpath("cli", "drive", "args.jl"),
        joinpath("cli", "go", "args.jl"),
        joinpath("cli", "setup", "args.jl"),
        joinpath("cli", "setup", "exit.jl"),
        joinpath("cli", "setup", "using_guard.jl"),
        joinpath("cli", "size", "args.jl"),
    )
end

function _integration_test_files()
    return (
        joinpath("drive", "local.jl"),
        joinpath("drive", "pkg.jl"),
        joinpath("drive", "log_via_script.jl"),
        joinpath("drive", "log_via_module.jl"),
        joinpath("drive", "pkg_develop.jl"),
        joinpath("demos", "with_kit.jl"),
        joinpath("demos", "without_kit.jl"),
    )
end

@testset "DistSSHKit" verbose=true begin
    @testset "unit" begin
        _run_test_files!(joinpath(@__DIR__, "unit"), _unit_test_files(), "unit")
    end
    @testset "integration" begin
        _run_test_files!(joinpath(@__DIR__, "integration"), _integration_test_files(), "integration")
    end
end
