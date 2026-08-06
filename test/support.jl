# Shared test infrastructure (barrel; mirrors cli/drive.jl + DistSSHKit/drive/runtime/).
# Guard: runtests and some unit files may both `include` this path; JETLS should not reload fragments.

if !isdefined(Main, :_child_julia_env)
    include(joinpath(@__DIR__, "support", "_common.jl"))
    include(joinpath(@__DIR__, "support", "testfiles.jl"))
    include(joinpath(@__DIR__, "support", "subprocess.jl"))
    include(joinpath(@__DIR__, "support", "host.jl"))
    include(joinpath(@__DIR__, "support", "drive.jl"))
    include(joinpath(@__DIR__, "support", "setup.jl"))
    include(joinpath(@__DIR__, "support", "staging.jl"))
    include(joinpath(@__DIR__, "support", "ssh_e2e.jl"))
end
