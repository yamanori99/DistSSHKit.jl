using Test

@testset "namespace" begin
    _with_tempdir() do tmp
        src = joinpath(tmp, "a.bin")
        write(src, "hello ns")
        h = DistSSHKit.file_sha256(src)
        @test length(h) == 64
        @test h == DistSSHKit.file_sha256(src)
        @test_throws ArgumentError DistSSHKit.file_sha256(joinpath(tmp, "missing"))

        dest = DistSSHKit.cache_file(src; project=tmp)
        @test dest == DistSSHKit.cache_path(h; project=tmp)
        @test isfile(dest)
        @test DistSSHKit.file_sha256(dest) == h
        dest2 = DistSSHKit.cache_file(src; project=tmp)
        @test dest2 == dest
        other = joinpath(tmp, "b.bin")
        write(other, "hello ns")
        @test DistSSHKit.cache_file(other; project=tmp) == dest
        @test DistSSHKit.cache_relpath(h) == joinpath(".distsshkit", "cache", "sha256", h)
        @test_throws ArgumentError DistSSHKit.cache_relpath("zz")

        withenv("DISTRIBUTED_OUTPUT_DIR" => nothing) do
            @test DistSSHKit.ns_path("a.bin"; project=tmp) == joinpath(
                DistSSHKit.canonical_local_path(tmp), "a.bin",
            )
            @test DistSSHKit.ns_path(src; project=tmp) == DistSSHKit.canonical_local_path(src)
        end
        out = joinpath(tmp, "slot")
        mkpath(out)
        write(joinpath(out, "a.bin"), "from slot")
        withenv("DISTRIBUTED_OUTPUT_DIR" => out) do
            @test DistSSHKit.ns_path("a.bin"; project=tmp) == joinpath(
                DistSSHKit.canonical_local_path(out), "a.bin",
            )
            @test DistSSHKit.ns_path("new.csv"; project=tmp) == joinpath(
                DistSSHKit.canonical_local_path(out), "new.csv",
            )
        end
    end

    @test DistSSHKit.cache_remote_dir("/remote/App") == joinpath(
        "/remote/App", ".distsshkit", "cache", "sha256",
    )

    _with_tempdir() do proj
        write(joinpath(proj, "Project.toml"), "name = \"CachePush\"\n")
        session = DistSSHKit.KitSession(project=proj, workers=["parent:1"])
        @test_throws ArgumentError DistSSHKit.push_cache!(session)
        empty = DistSSHKit.KitSession(project=proj, workers=["child:host1"])
        result = DistSSHKit.push_cache!(empty)
        @test result.ok
        @test isempty(result.hosts)
        src = joinpath(proj, "blob.bin")
        write(src, "cache-bytes")
        h = DistSSHKit.file_sha256(DistSSHKit.cache_file(src; project=proj))
        @test_throws ArgumentError DistSSHKit.push_cache!(
            DistSSHKit.KitSession(project=proj, workers=["child:host1"]);
            hashes=["not-a-hash"],
        )
        @test_throws ArgumentError DistSSHKit.push_cache!(
            DistSSHKit.KitSession(project=proj, workers=["child:host1"]);
            hashes=["a"^64],
        )
        _with_tempdir() do state_dir
            env = merge(
                _fake_setup_remote_env(state_dir),
                Dict(
                    "DISTRIBUTED_PROJECT_ROOT" => proj,
                    "DISTRIBUTED_REMOTE_PROJECT_ROOT" => "/fake/remote/CachePush",
                ),
            )
            withenv(env...) do
                DistSSHKit.apply_kit_cli_session!(DistSSHKit.KitCliSession(quiet=true, yes=true))
                sess = DistSSHKit.KitSession(
                    project=proj,
                    workers=["child:host1"],
                    remote="/fake/remote/CachePush",
                )
                ok = DistSSHKit.push_cache!(sess)
                @test ok.ok
                @test length(ok.hosts) == 1
                @test ok.hosts[1].ok
                subset = DistSSHKit.push_cache!(sess; hashes=[h])
                @test subset.ok
                withenv("DISTSSHKIT_TEST_RSYNC_FAIL" => "1") do
                    fail = DistSSHKit.push_cache!(sess)
                    @test !fail.ok
                    @test !fail.hosts[1].ok
                end
            end
        end
    end
end
