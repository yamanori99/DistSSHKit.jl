# Drive runtime fragments for `Main` only (not included into the DistSSHKit module).
# Loaded by `cli/drive.jl` after DistSSHKit / PROJECT_ROOT are bound.
# Kept under DistSSHKit/drive/runtime/ for layout; execution stays Main-scoped
# so Distributed remotecall closures serialize without requiring DistSSHKit on workers.

include(joinpath(@__DIR__, "runtime", "_common.jl"))
include(joinpath(@__DIR__, "runtime", "checks.jl"))
include(joinpath(@__DIR__, "runtime", "collect_tree.jl"))
include(joinpath(@__DIR__, "runtime", "workers.jl"))
include(joinpath(@__DIR__, "runtime", "init.jl"))
include(joinpath(@__DIR__, "runtime", "results.jl"))
include(joinpath(@__DIR__, "runtime", "run.jl"))
