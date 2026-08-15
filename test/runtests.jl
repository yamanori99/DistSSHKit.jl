#!/usr/bin/env julia
# DistSSHKit Pkg.test() entry: unit + integration (Aqua is CI-only).
# Does not include test/e2e.jl (real SSH; DISTSSHKIT_SSH_E2E=1 / up.sh --e2e).
# From a standalone kit checkout (this directory as the active project):
#   julia --project=. -e 'using Pkg; Pkg.test()'
#   julia --project=. test/runtests.jl
#
# Top-level `include`s (inside `@testset`s, not functions) so JETLS follows them.
# Each file already has a `@testset`; do not wrap another around `include`.
# New unit/integration files must be added here. Maintainer checks:
#   CONTRIBUTING.md ("Before opening a PR")
#   ./.github/jetls-check.sh

using Test
using DistSSHKit

include(joinpath(@__DIR__, "support.jl"))

@testset "DistSSHKit" verbose=true begin
    @testset "unit" verbose=true begin
        println("▸ unit/DistSSHKit/display.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "display.jl"))
        println("▸ unit/DistSSHKit/explain.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "explain.jl"))
        println("▸ unit/DistSSHKit/remote.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "remote.jl"))
        println("▸ unit/DistSSHKit/distributed.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "distributed.jl"))
        println("▸ unit/DistSSHKit/drive.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "drive.jl"))
        println("▸ unit/DistSSHKit/size.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "size.jl"))
        println("▸ unit/DistSSHKit/go.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "go.jl"))
        println("▸ unit/DistSSHKit/module.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "module.jl"))
        println("▸ unit/DistSSHKit/argv/args.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "argv", "args.jl"))
        println("▸ unit/DistSSHKit/argv/session.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "argv", "session.jl"))
        println("▸ unit/DistSSHKit/hosts.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "hosts.jl"))
        println("▸ unit/DistSSHKit/main_dispatch.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "main_dispatch.jl"))
        println("▸ unit/DistSSHKit/demos.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "demos.jl"))
        println("▸ unit/DistSSHKit/host_project_toml.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "host_project_toml.jl"))
        println("▸ unit/DistSSHKit/setup_api.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup_api.jl"))
        println("▸ unit/DistSSHKit/setup/checks.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "checks.jl"))
        println("▸ unit/DistSSHKit/setup/hosts.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "hosts.jl"))
        println("▸ unit/DistSSHKit/setup/git.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "git.jl"))
        println("▸ unit/DistSSHKit/setup/rsync.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "rsync.jl"))
        println("▸ unit/cli/drive/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "drive", "args.jl"))
        println("▸ unit/cli/go/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "go", "args.jl"))
        println("▸ unit/cli/setup/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "setup", "args.jl"))
        println("▸ unit/cli/setup/using_guard.jl")
        include(joinpath(@__DIR__, "unit", "cli", "setup", "using_guard.jl"))
        println("▸ unit/cli/size/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "size", "args.jl"))
    end

    @testset "integration" verbose=true begin
        println("▸ integration/setup/exit.jl")
        include(joinpath(@__DIR__, "integration", "setup", "exit.jl"))
        println("▸ integration/go/cli.jl")
        include(joinpath(@__DIR__, "integration", "go", "cli.jl"))
        println("▸ integration/go/overlap.jl")
        include(joinpath(@__DIR__, "integration", "go", "overlap.jl"))
        println("▸ integration/size/measure.jl")
        include(joinpath(@__DIR__, "integration", "size", "measure.jl"))
        println("▸ integration/drive/local.jl")
        include(joinpath(@__DIR__, "integration", "drive", "local.jl"))
        println("▸ integration/drive/api.jl")
        include(joinpath(@__DIR__, "integration", "drive", "api.jl"))
        println("▸ integration/drive/fail.jl")
        include(joinpath(@__DIR__, "integration", "drive", "fail.jl"))
        println("▸ integration/drive/pkg.jl")
        include(joinpath(@__DIR__, "integration", "drive", "pkg.jl"))
        println("▸ integration/drive/log_via_script.jl")
        include(joinpath(@__DIR__, "integration", "drive", "log_via_script.jl"))
        println("▸ integration/drive/log_via_module.jl")
        include(joinpath(@__DIR__, "integration", "drive", "log_via_module.jl"))
        println("▸ integration/drive/pkg_develop.jl")
        include(joinpath(@__DIR__, "integration", "drive", "pkg_develop.jl"))
        println("▸ integration/demos/with_kit.jl")
        include(joinpath(@__DIR__, "integration", "demos", "with_kit.jl"))
        println("▸ integration/demos/without_kit.jl")
        include(joinpath(@__DIR__, "integration", "demos", "without_kit.jl"))
    end
end
