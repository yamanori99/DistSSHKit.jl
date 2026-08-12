# Drive API — session, sync!, size! / size_plan, drive!, collect!, pipeline!.
# Result types live in `drive/types.jl` (included from `DistSSHKit.jl` before `setup/`).
# Worker execution core lives in `drive/runtime/` and is loaded into `Main` only
# (see `drive/_load_runtime.jl`, used by `cli/drive.jl` and `drive!`).

include(joinpath(@__DIR__, "drive", "session.jl"))
include(joinpath(@__DIR__, "drive", "bridge.jl"))
include(joinpath(@__DIR__, "drive", "sync.jl"))
include(joinpath(@__DIR__, "drive", "instantiate.jl"))
include(joinpath(@__DIR__, "drive", "size.jl"))
include(joinpath(@__DIR__, "drive", "tokens.jl"))
include(joinpath(@__DIR__, "drive", "api.jl"))
include(joinpath(@__DIR__, "drive", "collect.jl"))
include(joinpath(@__DIR__, "drive", "pipeline.jl"))
