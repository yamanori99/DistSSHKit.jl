module TestAqua

using Aqua
using DistSSHKit
using Test

@testset "Aqua.jl" begin
    Aqua.test_all(DistSSHKit)
end

end # module
