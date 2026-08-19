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

# In-process default matches TTY CLI (`:progress`), not module-load `:verbose`
# or a pipe. Child CLI processes still auto-detect their own stdout.
DistSSHKit.set_kit_verbosity!(:progress)

# Keep `include(joinpath(@__DIR__, …))` at this top level (JETLS). Only the
# banner is counted. Update `_RUNTEST_N` when adding a file below.
const _RUNTEST_N = 42
const _RUNTEST_I = Ref(0)
function _runtest_announce(rel::AbstractString)
    _RUNTEST_I[] += 1
    println("[$( _RUNTEST_I[])/$_RUNTEST_N]  $rel")
    flush(stdout)
    return nothing
end

@testset "DistSSHKit" verbose=true begin
    @testset "unit" verbose=true begin
        _runtest_announce("unit/DistSSHKit/display.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "display.jl"))
        _runtest_announce("unit/DistSSHKit/explain.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "explain.jl"))
        _runtest_announce("unit/DistSSHKit/remote.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "remote.jl"))
        _runtest_announce("unit/DistSSHKit/distributed.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "distributed.jl"))
        _runtest_announce("unit/DistSSHKit/drive.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "drive.jl"))
        _runtest_announce("unit/DistSSHKit/drive/collect_tree.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "drive", "collect_tree.jl"))
        _runtest_announce("unit/DistSSHKit/drive/workers.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "drive", "workers.jl"))
        _runtest_announce("unit/DistSSHKit/size.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "size.jl"))
        _runtest_announce("unit/DistSSHKit/go.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "go.jl"))
        _runtest_announce("unit/DistSSHKit/module.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "module.jl"))
        _runtest_announce("unit/DistSSHKit/execute.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "execute.jl"))
        _runtest_announce("unit/DistSSHKit/argv/args.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "argv", "args.jl"))
        _runtest_announce("unit/DistSSHKit/argv/session.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "argv", "session.jl"))
        _runtest_announce("unit/DistSSHKit/hosts.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "hosts.jl"))
        _runtest_announce("unit/DistSSHKit/main_dispatch.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "main_dispatch.jl"))
        _runtest_announce("unit/DistSSHKit/demos.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "demos.jl"))
        _runtest_announce("unit/DistSSHKit/host_project_toml.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "host_project_toml.jl"))
        _runtest_announce("unit/DistSSHKit/setup_api.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup_api.jl"))
        _runtest_announce("unit/DistSSHKit/setup/checks.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "checks.jl"))
        _runtest_announce("unit/DistSSHKit/setup/hosts.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "hosts.jl"))
        _runtest_announce("unit/DistSSHKit/setup/git.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "git.jl"))
        _runtest_announce("unit/DistSSHKit/setup/rsync.jl")
        include(joinpath(@__DIR__, "unit", "DistSSHKit", "setup", "rsync.jl"))
        _runtest_announce("unit/cli/drive/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "drive", "args.jl"))
        _runtest_announce("unit/cli/go/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "go", "args.jl"))
        _runtest_announce("unit/cli/setup/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "setup", "args.jl"))
        _runtest_announce("unit/cli/setup/using_guard.jl")
        include(joinpath(@__DIR__, "unit", "cli", "setup", "using_guard.jl"))
        _runtest_announce("unit/cli/setup/main.jl")
        include(joinpath(@__DIR__, "unit", "cli", "setup", "main.jl"))
        _runtest_announce("unit/cli/size/args.jl")
        include(joinpath(@__DIR__, "unit", "cli", "size", "args.jl"))
    end

    @testset "integration" verbose=true begin
        _runtest_announce("integration/cli/help.jl")
        include(joinpath(@__DIR__, "integration", "cli", "help.jl"))
        _runtest_announce("integration/setup/exit.jl")
        include(joinpath(@__DIR__, "integration", "setup", "exit.jl"))
        _runtest_announce("integration/go/cli.jl")
        include(joinpath(@__DIR__, "integration", "go", "cli.jl"))
        _runtest_announce("integration/go/overlap.jl")
        include(joinpath(@__DIR__, "integration", "go", "overlap.jl"))
        _runtest_announce("integration/size/measure.jl")
        include(joinpath(@__DIR__, "integration", "size", "measure.jl"))
        _runtest_announce("integration/drive/local.jl")
        include(joinpath(@__DIR__, "integration", "drive", "local.jl"))
        _runtest_announce("integration/drive/api.jl")
        include(joinpath(@__DIR__, "integration", "drive", "api.jl"))
        _runtest_announce("integration/drive/fail.jl")
        include(joinpath(@__DIR__, "integration", "drive", "fail.jl"))
        _runtest_announce("integration/drive/pkg.jl")
        include(joinpath(@__DIR__, "integration", "drive", "pkg.jl"))
        _runtest_announce("integration/drive/log_via_script.jl")
        include(joinpath(@__DIR__, "integration", "drive", "log_via_script.jl"))
        _runtest_announce("integration/drive/log_via_module.jl")
        include(joinpath(@__DIR__, "integration", "drive", "log_via_module.jl"))
        _runtest_announce("integration/drive/pkg_develop.jl")
        include(joinpath(@__DIR__, "integration", "drive", "pkg_develop.jl"))
        _runtest_announce("integration/demos/with_kit.jl")
        include(joinpath(@__DIR__, "integration", "demos", "with_kit.jl"))
        _runtest_announce("integration/demos/without_kit.jl")
        include(joinpath(@__DIR__, "integration", "demos", "without_kit.jl"))
    end
end
