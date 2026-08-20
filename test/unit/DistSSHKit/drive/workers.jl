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

        @testset "cleanup_stale_workers! skips localhost with no SSH hosts" begin
            withenv("DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL" => nothing) do
                mktemp() do path, io
                    redirect_stdout(io) do
                        Main.cleanup_stale_workers!(_EMPTY_DRIVE_HOSTS)
                    end
                    flush(io)
                    @test !occursin("Cleaning up stale workers", read(path, String))
                end
            end
        end

        @testset "cleanup_stale_workers! DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL" begin
            withenv("DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL" => "1") do
                mktemp() do path, io
                    redirect_stdout(io) do
                        Main.cleanup_stale_workers!(
                            Tuple{String,Union{Int,Nothing}}[("example.invalid", 1)],
                        )
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

@testset "drive heartbeat" begin
    @testset "_heartbeat_config" begin
        cfg = DistSSHKit._heartbeat_config(Dict{String,String}())
        @test cfg.interval == 30.0
        @test cfg.deadline == 600.0
        cfg = DistSSHKit._heartbeat_config(Dict(
            "DISTRIBUTED_HEARTBEAT_INTERVAL_SEC" => "2",
            "DISTRIBUTED_HEARTBEAT_DEADLINE_SEC" => "9",
        ))
        @test cfg.interval == 2.0
        @test cfg.deadline == 9.0
        cfg = DistSSHKit._heartbeat_config(Dict(
            "DISTRIBUTED_HEARTBEAT_INTERVAL_SEC" => "nope",
            "DISTRIBUTED_HEARTBEAT_DEADLINE_SEC" => "-1",
        ))
        @test cfg.interval == 30.0
        @test cfg.deadline == 600.0
    end

    @testset "_master_alive" begin
        @test DistSSHKit._master_alive(0.0, 10.0, 10.0)
        @test DistSSHKit._master_alive(0.0, 10.0, 9.9)
        @test !DistSSHKit._master_alive(0.0, 10.0, 10.1)
    end

    function _wait_flag(flag::Ref{Bool}; timeout::Float64=2.0)
        t0 = time()
        while !flag[] && (time() - t0) < timeout
            sleep(0.02)
        end
        return flag[]
    end

    @testset "_run_heartbeat! silent stall trips on_dead" begin
        stop = Ref(false)
        dead = Ref(false)
        ch = Channel{Nothing}(0)
        hb = DistSSHKit._run_heartbeat!(
            stop, 0.05, 0.12;
            ping=() -> take!(ch),
            on_dead=() -> (dead[] = true),
        )
        try
            @test _wait_flag(dead)
            @test istaskstarted(hb.prober)
            @test istaskstarted(hb.watchdog)
        finally
            stop[] = true
            close(ch)
        end
    end

    @testset "_run_heartbeat! live ping does not trip" begin
        stop = Ref(false)
        dead = Ref(false)
        DistSSHKit._run_heartbeat!(
            stop, 0.05, 0.12;
            ping=() -> true,
            on_dead=() -> (dead[] = true),
        )
        try
            sleep(0.35)
            @test !dead[]
        finally
            stop[] = true
        end
    end

    @testset "_run_heartbeat! blip then recover" begin
        stop = Ref(false)
        dead = Ref(false)
        n = Ref(0)
        DistSSHKit._run_heartbeat!(
            stop, 0.04, 0.35;
            ping=() -> (n[] += 1; n[] <= 2 && error("blip"); true),
            on_dead=() -> (dead[] = true),
        )
        try
            sleep(0.45)
            @test !dead[]
            @test n[] > 2
        finally
            stop[] = true
        end
    end

    @testset "_run_heartbeat! stop ends both tasks" begin
        stop = Ref(false)
        hb = DistSSHKit._run_heartbeat!(
            stop, 0.03, 10.0;
            ping=() -> true,
            on_dead=() -> error("should not die"),
        )
        stop[] = true
        wait(hb.prober)
        wait(hb.watchdog)
        @test istaskdone(hb.prober)
        @test istaskdone(hb.watchdog)
    end
end
