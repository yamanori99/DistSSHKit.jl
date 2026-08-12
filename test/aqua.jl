module TestAqua

# Aqua's dependency-based checks (`stale_deps`, `deps_compat`, `ambiguities`
# across all loaded packages) require a real, top-level package module — not
# the `Main.DistSSHKit` produced by `include`ing `src/DistSSHKit.jl` directly.
# This file therefore `using DistSSHKit` instead of reusing the module already
# loaded by `runtests.jl`. That resolves under both `Pkg.test()` and plain
# `--project=test` activation (e.g. jetls) via the `[sources]` path entry in
# `test/Project.toml` (the checkout under test).

using Aqua
using DistSSHKit
using Test

@testset "Aqua.jl" begin
    Aqua.test_all(
        DistSSHKit;
        # `Pkg`/`Distributed` are used by CLI/runtime under `src/cli/` and
        # `src/DistSSHKit/drive/runtime/`, which are `include`d into `Main` (not into the
        # `DistSSHKit` module). Aqua only sees `using` inside the module itself.
        stale_deps=false,
    )
end

end # module
