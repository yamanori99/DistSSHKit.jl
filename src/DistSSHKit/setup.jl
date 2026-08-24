# Setup cores shared by CLI `setup` and API `sync!` (rsync + git + ops).

include(joinpath(@__DIR__, "setup", "progress.jl"))
include(joinpath(@__DIR__, "setup", "rsync.jl"))
include(joinpath(@__DIR__, "setup", "git.jl"))
include(joinpath(@__DIR__, "setup", "hosts.jl"))
include(joinpath(@__DIR__, "setup", "checks.jl"))
include(joinpath(@__DIR__, "setup", "remote_ops.jl"))
