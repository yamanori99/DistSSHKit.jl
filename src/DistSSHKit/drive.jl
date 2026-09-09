# Drive API — session, sync!, instantiate!, setup!, size!,
# drive!, collect!, pipeline!.
# Result types live in `drive/types.jl` (included from `DistSSHKit.jl` before `setup/`).
# Worker execution core lives in `drive/runtime/` (included from `DistSSHKit.jl`
# after heartbeat.jl). Worker bootstrap is `include_string` / `Core.eval` on
# Main so remotes do not need DistSSHKit.

include(joinpath(@__DIR__, "drive", "session.jl"))
include(joinpath(@__DIR__, "drive", "bridge.jl"))
include(joinpath(@__DIR__, "drive", "sync.jl"))
include(joinpath(@__DIR__, "drive", "instantiate.jl"))
include(joinpath(@__DIR__, "drive", "setup_api.jl"))
include(joinpath(@__DIR__, "drive", "size.jl"))
include(joinpath(@__DIR__, "drive", "tokens.jl"))
include(joinpath(@__DIR__, "drive", "api.jl"))
include(joinpath(@__DIR__, "drive", "collect.jl"))
include(joinpath(@__DIR__, "drive", "pipeline.jl"))
