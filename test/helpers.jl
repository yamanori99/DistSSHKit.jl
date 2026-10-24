# Capture and child-process helpers. Not a guarantee of CLI wording.

# Run's CLI scripts write these even when they were absent. `withenv` only
# restores keys it was given, so name them here or `"1"` stays after the call.
const _CLI_WRITTEN_KEYS = (
    "DISTSSHKIT_CLI_SUBCOMMAND_DONE",
    "DISTRIBUTED_PROJECT_ROOT",
    "DIST_SSH_KIT_CLI_INCLUDE",
)

"""Drop developer CLI env so a test sees the package defaults."""
function _cli_env_isolation()
    ks = Set{String}()
    for k in keys(ENV)
        if startswith(k, "DISTSSHKIT_") || k == "DISTRIBUTED_SSH_OPTS"
            push!(ks, String(k))
        end
    end
    union!(ks, _CLI_WRITTEN_KEYS)
    return [k => nothing for k in ks]
end

"""Run `f` with CLI env cleared. On throw, log `args` when given and return a failing code."""
function _stdio_capture(f; args = nothing)
    saved_args = copy(ARGS)
    try
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
    finally
        empty!(ARGS)
        append!(ARGS, saved_args)
    end
end

function _main_capture(args)
    return _stdio_capture(() -> DistSSHKit.main(args); args = args)
end

"""`julia -m <pkg>` as DistSSHBase builds it for that outermost entry."""
function _owner_cli_m(pkg::Symbol)::String
    return DistSSHRun.DistSSHBase.with_cli_entry(pkg) do
        DistSSHRun.DistSSHBase.cli_m()
    end
end

"""
Owner `main` for `args`, with the CLI entry forced to DistSSHKit.

An inner `main` does not replace an outer entry, so the page uses Kit's
heading (`cli_heading` / `cli_qhost_heading`) rather than the owner's.
This calls `owner_main` (Run or Queue). It does not call `DistSSHKit.main`.
"""
function _owner_capture(owner_main, args::Vector{String})
    return _stdio_capture(; args = args) do
        DistSSHRun.DistSSHBase.with_cli_entry(:DistSSHKit) do
            owner_main(args)
        end
    end
end

"""
Kit's `(code, stdout, stderr)` for `kit_args` equals the owner's for `owner_args`.

Both exits are 0. The page must not name the other package's `julia -m`
line: equality is rendered under Kit's entry, so a hardcoded owner entry
would match on both sides and still be wrong.
"""
function _test_same_page(kit_args, owner_main, owner_args = kit_args)
    got = _main_capture(kit_args)
    want = _owner_capture(owner_main, owner_args)
    @test got[1] == want[1] == 0
    @test got[2] == want[2]
    @test got[3] == want[3]
    text = got[2] * got[3]
    @test !occursin(_owner_cli_m(:DistSSHRun), text)
    @test !occursin(_owner_cli_m(:DistSSHQueue), text)
    return got
end

"""PATH-front `ssh` that records argv and exits 0. Does not open a connection."""
function _with_fake_ssh(f)
    return mktempdir() do bin
        log = joinpath(bin, "argv")
        path = joinpath(bin, "ssh")
        write(path, "#!/bin/sh\nprintf '%s\\n' \"\$@\" >> '$(log)'\nexit 0\n")
        chmod(path, 0o755)
        withenv(
            "PATH" => bin * ":" * ENV["PATH"],
            "DISTSSHKIT_QUIET" => nothing,
            "DISTSSHKIT_TEST_SSH" => nothing,
        ) do
            f(log)
        end
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
