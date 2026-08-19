using Test
using Distributed

# Oracle: worker lifecycle helpers in drive/runtime/workers.jl.
# Those fragments are Main-scoped (`cli/drive.jl` / `_ensure_drive_fragments!`).
# Do not `include` the runtime sources from this file: JetLS follows top-level
# `include()` from `test/runtests.jl` and would then type-check production
# `workers.jl` inside a test module (wrong `PROJECT_ROOT`, `hosts::Vector{String}`
# unpacked as `Char`). Load the same way `drive!` does, at top level, so
# `Main.*` methods exist before this file's `@testset` is lowered (world age).

const _EMPTY_DRIVE_HOSTS = Tuple{String,Union{Int,Nothing}}[]

let _frag_root = mktempdir()
    try
        DistSSHKit._ensure_drive_fragments!(_frag_root)
    finally
        rm(_frag_root; recursive=true, force=true)
    end
end

@testset "drive workers lifecycle" begin
    _with_tempdir() do tmp
        DistSSHKit._ensure_drive_fragments!(tmp)

        @testset "register_worker_cleanup! lone master is a no-op" begin
            @test nprocs() == 1
            @test workers() == [1]
            cleanup = Main.register_worker_cleanup!(String[])
            # Must not rmprocs([1]) / warn "process 1 not removed".
            @test cleanup() === nothing
            @test nprocs() == 1
            @test workers() == [1]
            @test cleanup() === nothing
        end

        @testset "register_worker_cleanup! removes added workers" begin
            addprocs(2; topology=:master_worker)
            added = workers()
            @test length(added) == 2
            try
                cleanup = Main.register_worker_cleanup!(String[])
                cleanup()
                @test nprocs() == 1
                @test workers() == [1]
                @test cleanup() === nothing
            finally
                for w in added
                    w in workers() && rmprocs(w; waitfor=2.0)
                end
            end
        end

        @testset "register_worker_cleanup! guard trips before later workers" begin
            addprocs(1; topology=:master_worker)
            pre = workers()[end]
            try
                cleanup = Main.register_worker_cleanup!(String[])
                cleanup()
                @test pre ∉ workers()
                addprocs(1; topology=:master_worker)
                other = workers()[end]
                try
                    cleanup()
                    @test other in workers()
                finally
                    other in workers() && rmprocs(other; waitfor=2.0)
                end
            finally
                pre in workers() && rmprocs(pre; waitfor=2.0)
            end
        end

        @testset "cleanup_stale_workers! DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL" begin
            withenv("DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL" => "1") do
                mktemp() do path, io
                    redirect_stdout(io) do
                        Main.cleanup_stale_workers!(_EMPTY_DRIVE_HOSTS)
                    end
                    flush(io)
                    @test !occursin("Cleaning up stale workers", read(path, String))
                end
            end
        end

        @testset "add_drive_workers! errors when nothing joins" begin
            script = joinpath(tmp, "job.jl")
            write(script, "")
            @test_throws ErrorException redirect_stdout(devnull) do
                Main.add_drive_workers!(
                    _EMPTY_DRIVE_HOSTS, 0, nothing, nothing, tmp, script,
                )
            end
        end

        @testset "add_drive_workers! adds only local workers when requested" begin
            script = joinpath(tmp, "job.jl")
            write(script, "")
            before = Set(workers())
            successful_hosts = redirect_stdout(devnull) do
                Main.add_drive_workers!(
                    _EMPTY_DRIVE_HOSTS, 2, nothing, nothing, tmp, script,
                )
            end
            added = setdiff(Set(workers()), before)
            try
                @test isempty(successful_hosts)
                @test length(added) == 2
                @test nprocs() > 1
                for w in added
                    @test get(Main.RUNNER_WORKER_PROJECT_DIRS, w, nothing) == tmp
                end
            finally
                for w in added
                    w in workers() && rmprocs(w; waitfor=2.0)
                end
            end
        end
    end
end
