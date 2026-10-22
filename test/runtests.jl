#!/usr/bin/env julia
# Meta-package checks. The run surface is tested in DistSSHRun, the queue in
# DistSSHQueue. This suite checks reexports and `julia -m DistSSHKit` routing.

using Test
using DistSSHKit
using DistSSHQueue
using DistSSHRun

include("helpers.jl")

module _PublicOnlyProbe
    function kept_out end
    public kept_out
    function shown end
    export shown
end

@testset "DistSSHKit" verbose = true begin
    include("reexport.jl")
    include("routing.jl")
    include("consistency.jl")
    include("hop.jl")
    include("version.jl")
    include("state.jl")
    include("subprocess.jl")
    include("ssh_opts.jl")
end
