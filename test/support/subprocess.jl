if !isdefined(Main, :_child_julia_env)

"""ENV for child `julia` / `drive` processes.

Drop `Pkg.test`'s `JULIA_LOAD_PATH` so `--project=` resolves packages (and
stdlibs like Serialization) like a normal user invocation.
"""
function _child_julia_env(extra::AbstractDict=Dict{String,String}())
    # In-process `_run_kit_cli_script` sets DISTSSHKIT_CLI_SUBCOMMAND_DONE so a
    # nested `main` does not run twice. Children must not inherit that, or
    # `DistSSHKit.main` / `-m DistSSHKit` returns 0 with empty output.
    skip = Set((
        "JULIA_LOAD_PATH",
        "DISTSSHKIT_CLI_SUBCOMMAND_DONE",
        "DIST_SSH_KIT_CLI_INCLUDE",
    ))
    env = Dict{String,String}(
        String(k) => String(v) for (k, v) in ENV if !isempty(v) && !(String(k) in skip)
    )
    env["JULIA_PKG_PRECOMPILE_AUTO"] = get(ENV, "JULIA_PKG_PRECOMPILE_AUTO", "0")
    # Avoid broad pkill in drive; each child cleans its own workers via rmprocs.
    env["DISTSSHKIT_SKIP_GLOBAL_WORKER_PKILL"] = "1"
    for (k, v) in extra
        env[String(k)] = String(v)
    end
    return env
end

function _run_subprocess(cmd::Cmd)
    out = IOBuffer()
    proc = run(pipeline(ignorestatus(cmd), stdout=out, stderr=out), wait=true)
    return proc, String(take!(out))
end


"""Assert subprocess exit code 0; on failure print captured output first."""
function _assert_proc_ok(proc, combined::AbstractString; label::AbstractString="subprocess")
    if proc.exitcode != 0
        println(stderr, "──── $(label) failed (exit=$(proc.exitcode)) ────")
        println(stderr, combined)
        println(stderr, "──── end $(label) output ────")
    end
    @test proc.exitcode == 0
end

end
