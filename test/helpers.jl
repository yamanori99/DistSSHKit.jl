# Capture and child-process helpers. Not a guarantee of CLI wording.

"""Drop developer CLI env so a test sees the package defaults."""
function _cli_env_isolation()
    pairs = Pair{String, Nothing}[]
    for k in keys(ENV)
        if startswith(k, "DISTSSHKIT_") || k == "DISTRIBUTED_SSH_OPTS"
            push!(pairs, k => nothing)
        end
    end
    return pairs
end

"""Run `f` with CLI env cleared. On throw, log `args` when given and return a failing code."""
function _stdio_capture(f; args = nothing)
    return mktemp() do out_path, out_io
        mktemp() do err_path, err_io
            code = try
                withenv(_cli_env_isolation()...) do
                    redirect_stdout(out_io) do
                        redirect_stderr(err_io) do
                            f()
                        end
                    end
                end
            catch e
                @error "captured call failed" args exception = (e, catch_backtrace())
                typemin(Cint)
            end
            flush(out_io)
            flush(err_io)
            return code, read(out_path, String), read(err_path, String)
        end
    end
end

function _main_capture(args)
    return _stdio_capture(() -> DistSSHKit.main(args); args = args)
end

"""PATH-front `ssh` that records argv and exits 0. Does not open a connection."""
function _with_fake_ssh(f)
    bin = mktempdir()
    log = joinpath(bin, "argv")
    path = joinpath(bin, "ssh")
    write(path, "#!/bin/sh\nprintf '%s\\n' \"\$@\" >> '$(log)'\nexit 0\n")
    chmod(path, 0o755)
    return withenv(
        "PATH" => bin * ":" * ENV["PATH"],
        "DISTSSHKIT_QUIET" => nothing,
        "DISTSSHKIT_TEST_SSH" => nothing,
    ) do
        f(log)
    end
end

"""`julia -m DistSSHKit` in a child. Stdout and stderr are temp files (Julia 1.13)."""
function _kit_proc(julia, app, env, args)
    return mktemp() do out_path, out_io
        mktemp() do err_path, err_io
            p = run(
                pipeline(
                    ignorestatus(
                        setenv(
                            `$julia --startup-file=no --project=$app -m DistSSHKit $args`, env,
                        )
                    ); stdout = out_io, stderr = err_io
                )
            )
            flush(out_io)
            flush(err_io)
            return p.exitcode, read(out_path, String), read(err_path, String)
        end
    end
end
