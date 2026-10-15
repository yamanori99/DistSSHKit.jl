# Child `julia -m DistSSHKit` exit codes. Set DISTSSHKIT_SKIP_SUBPROCESS_TESTS=1
# to skip. Not a guarantee of help text beyond `drive -h`.

@testset "app project" begin
    if get(ENV, "DISTSSHKIT_SKIP_SUBPROCESS_TESTS", "") == "1"
        @test_skip "subprocess"
    else
        app = mktempdir()
        kit = something(pkgdir(DistSSHKit), pwd())
        write(
            joinpath(app, "Project.toml"),
            """
            name = "AppOnlyKit"
            uuid = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"
            version = "0.0.1"

            [deps]
            DistSSHKit = "ceec0504-c968-4be5-b215-667cae0e8f81"

            [sources]
            DistSSHKit = {path = $(repr(kit))}
            """,
        )
        julia = joinpath(Sys.BINDIR, "julia")
        child_env = copy(ENV)
        delete!(child_env, "JULIA_LOAD_PATH")
        delete!(child_env, "JULIA_PROJECT")
        for k in collect(keys(child_env))
            if startswith(k, "DISTSSHKIT_") || k == "DISTRIBUTED_SSH_OPTS"
                delete!(child_env, k)
            end
        end
        inst_code, inst_out, inst_err = mktemp() do out_path, out_io
            mktemp() do err_path, err_io
                p = run(
                    pipeline(
                        ignorestatus(
                            setenv(
                                `$julia --startup-file=no --project=$app -e "using Pkg; Pkg.instantiate()"`,
                                child_env,
                            )
                        ); stdout = out_io, stderr = err_io
                    )
                )
                flush(out_io)
                flush(err_io)
                return p.exitcode, read(out_path, String), read(err_path, String)
            end
        end
        if inst_code != 0
            @info "Pkg.instantiate failed" stdout = inst_out stderr = inst_err
            @test false
        else
            cases = [
                (String[], 1),
                (["--version"], 0),
                (["-h"], 0),
                (["bogus"], 1),
                (["x.jl"], 1),
                (["drive", "-h"], 0),
                (["submit", "-h"], 0),
            ]
            for (args, want) in cases
                code, out, err = _kit_proc(julia, app, child_env, args)
                @test code == want
                if args == ["drive", "-h"]
                    @test occursin("DistSSHKit drive", out)
                    @test !occursin("Package DistSSHRun not found", err)
                end
            end
        end
    end
end
