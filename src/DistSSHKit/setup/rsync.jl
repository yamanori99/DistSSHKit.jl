# Rsync local project tree to SSH hosts (shared by `setup --rsync` and `sync!`).

"""Julia argv for `DISTSSHKIT_TEST_SSH` / `.jl` rsync doubles (`--compile=min`)."""
function _test_double_julia_argv(script::AbstractString)::Vector{String}
    julia = joinpath(Sys.BINDIR, Base.julia_exename())
    return [julia, "--startup-file=no", "--compile=min", abspath(script)]
end

function _host_sync_rsync_transport()::String
    custom = strip(get(ENV, "DISTSSHKIT_TEST_SSH", ""))
    if !isempty(custom)
        return join(_test_double_julia_argv(custom), " ")
    end
    return Base.shell_escape(_ssh_exe()) * " " * join(ssh_opts(), " ")
end

function _host_sync_rsync_argv()::Vector{String}
    custom = strip(get(ENV, "DISTSSHKIT_TEST_RSYNC", ""))
    if !isempty(custom)
        path = abspath(custom)
        # `.jl` doubles spawn Julia; prefer `.sh` so collect tests do not nest a
        # second compiler (1.11 GHA OOM).
        endswith(path, ".jl") && return _test_double_julia_argv(path)
        return ["sh", path]
    end
    return [_host_tool_exe("rsync")]
end

"""Run rsync with `--files-from` via a temp list, not `stdin`.

Julia 1.14 `pipeline(; stdin=buf)` waits for the write and throws `EPIPE` if the
child exits without reading stdin (fake rsync, or rsync dying on argv). A list
file is the same rsync contract without that pipe.
"""
function _run_rsync_files_from(
    rsync_bin::Vector{String},
    opts::Vector{String},
    src::AbstractString,
    dest::AbstractString,
    files::Vector{String};
    stderr=stderr,
)
    mktemp() do path, io
        for rel in files
            println(io, rel)
        end
        close(io)
        cmd = Cmd(vcat(rsync_bin, opts, ["--files-from=$path", String(src), String(dest)]))
        run(pipeline(cmd; stderr=stderr))
    end
    return nothing
end

function _host_sync_remote_shell_cmd(host::String, remote_script::String)::Cmd
    custom = strip(get(ENV, "DISTSSHKIT_TEST_SSH", ""))
    if !isempty(custom)
        return Cmd(vcat(_test_double_julia_argv(custom), [host, remote_script]))
    end
    return _ssh_cmd([ssh_opts()..., host, remote_script])
end

"""Remote shell snippet classifying `remote_path` as MISSING / EMPTY / NONEMPTY."""
function _remote_dest_status_script(remote_path::AbstractString)::String
    pq = _remote_shell_path_word(remote_path)
    # Leading marker keeps test doubles and parsers stable.
    return string(
        "echo DISTSSHKIT_DEST_STATUS; ",
        "if [ ! -e $pq ]; then echo MISSING; ",
        "elif [ ! -d $pq ]; then echo NONEMPTY; ",
        "elif [ -z \"\$(ls -A $pq 2>/dev/null)\" ]; then echo EMPTY; ",
        "else echo NONEMPTY; fi",
    )
end

"""
Classify `remote_path` on `host`: `:missing`, `:empty`, or `:nonempty`.

Uses `_host_sync_remote_shell_cmd` (honors `DISTSSHKIT_TEST_SSH`).
On SSH/script failure, returns `:nonempty` (fail closed — refuse overwrite).
"""
function remote_dest_status(host::String, remote_path::AbstractString)::Symbol
    try
        result = read(
            pipeline(
                _host_sync_remote_shell_cmd(host, _remote_dest_status_script(remote_path));
                stderr=devnull,
            ),
            String,
        )
        for line in eachline(IOBuffer(result))
            s = strip(line)
            s == "MISSING" && return :missing
            s == "EMPTY" && return :empty
            s == "NONEMPTY" && return :nonempty
        end
        return :nonempty
    catch
        return :nonempty
    end
end

function remote_dest_busy_message(host::AbstractString, remote_path::AbstractString)::String
    return string(
        "remote path already exists on ",
        host,
        ": ",
        remote_path,
        " (refusing to overwrite). ",
        "Delete it first, e.g.: julia --project=. -m DistSSHKit setup --delete ",
        host,
    )
end

function _remote_dir_exists(host::String, remote_path::String)::Bool
    st = remote_dest_status(host, remote_path)
    return st === :empty || st === :nonempty
end

function _ensure_remote_dir(host::String, remote_path::String)::Bool
    pq = _remote_shell_path_word(remote_path)
    try
        run(
            pipeline(
                _host_sync_remote_shell_cmd(host, "mkdir -p $pq");
                stderr=devnull,
                stdout=devnull,
            ),
        )
        return true
    catch e
        _rethrow_missing_host_tool(e)
        return false
    end
end

function _print_rsync_safety_banner!(
    local_root::AbstractString,
    remote_path::AbstractString,
    hosts::Vector{String},
    path_anchor::AbstractString,
)
    # Consent text: always on the terminal (same gate as `kit_confirm`).
    print_warn("  This bypasses git entirely: no commit, no push/pull, no hash check.\n")
    println_fatal("  Local and remote git commits will likely disagree afterwards.")
    println_fatal("  That is fine: `drive` does not require git parity by default.")
    println_fatal("  Use `drive --require-git` only with git-managed remotes.")
    println_fatal("  Prefer `setup --sync` when you need the git-commit reproducibility guarantee.")
    println_fatal()
    print_warn("  Safety: refuses if the remote path already has any files.\n")
    println_fatal("  To replace an existing tree, run `setup --delete` first, then `--rsync`.")
    println_fatal("  Mirrors onto a missing/empty path (`--delete`); excludes `.git/` and `.distsshkit/`; honors `.gitignore`.")
    println_fatal()
    println_fatal("  Local project: $(display_path(local_root, path_anchor))")
    println_fatal("  Remote path: $remote_path")
    println_fatal("  Hosts: $(join(hosts, ", "))")
    println_fatal()
    return nothing
end

"""
Run rsync for one host. Returns
`(; status=:ok|:busy|:mkdir_fail, message, dir_created)`.
Throws on rsync command failure after setup.
"""
function _rsync_one_host!(
    host::String,
    local_root::AbstractString,
    remote_path::AbstractString,
    ssh_cmd_str::String,
)
    st = remote_dest_status(host, remote_path)
    if st === :nonempty
        return (;
            status=:busy,
            message=remote_dest_busy_message(host, remote_path),
            dir_created=false,
        )
    end
    dir_created = false
    if st === :missing
        if !_ensure_remote_dir(host, remote_path)
            return (;
                status=:mkdir_fail,
                message="could not create remote directory",
                dir_created=false,
            )
        end
        dir_created = true
    end
    rsync_cmd = Cmd(
        vcat(
            _host_sync_rsync_argv(),
            String[
                "-az",
                "--delete",
                "-e",
                ssh_cmd_str,
                "--exclude",
                ".git/",
                "--exclude",
                ".distsshkit/",
                "--filter",
                ":- .gitignore",
                local_root * "/",
                string(host, ":", remote_path, "/"),
            ],
        ),
    )
    run(pipeline(rsync_cmd; stderr=stderr))
    return (; status=:ok, message="", dir_created=dir_created)
end

"""
    rsync_project_to_hosts!(
        hosts, local_root, remote_path;
        confirm=true, report=false, path_anchor=local_root,
    )

Rsync `local_root/` to `remote_path` on each SSH host. Returns
`(cancelled, succeeded, failed, host_results)`.

Refuses hosts where `remote_path` already has any entries (safety). Use
`setup --delete` first to replace an existing tree. Missing or empty
directories are created/filled.

When `confirm=true`, prints warnings and requires typing `rsync` (unless
[`kit_noninteractive`](@ref) / `--yes` is active — then confirmation is skipped,
but the nonempty-path refusal still applies).
"""
function rsync_project_to_hosts!(
    hosts::Vector{String},
    local_root::AbstractString,
    remote_path::AbstractString;
    confirm::Bool=true,
    report::Bool=false,
    path_anchor::AbstractString=local_root,
)::NamedTuple
    local_root = canonical_local_path(local_root)
    remote_path = String(remote_path)
    path_anchor = canonical_local_path(path_anchor)

    if confirm && !kit_noninteractive()
        _print_rsync_safety_banner!(local_root, remote_path, hosts, path_anchor)
        if !kit_confirm("Type 'rsync' to confirm: "; keyword="rsync")
            println_fatal("Cancelled.")
            return (
                cancelled=true,
                succeeded=0,
                failed=0,
                host_results=HostResult[],
            )
        end
        println_fatal()
    end

    ssh_cmd_str = _host_sync_rsync_transport()
    n_hosts = length(hosts)
    host_results = Vector{HostResult}(undef, n_hosts)
    jobs = kit_host_jobs()
    sequential_spin = report && jobs == 1

    function _rsync_host_result(host::String)::HostResult
        dir_created = false
        try
            outcome = if sequential_spin
                kit_spin!("  $host: ") do
                    _rsync_one_host!(host, local_root, remote_path, ssh_cmd_str)
                end
            else
                _rsync_one_host!(host, local_root, remote_path, ssh_cmd_str)
            end
            if outcome.status === :busy || outcome.status === :mkdir_fail
                return HostResult(host, false, outcome.message)
            end
            dir_created = outcome.dir_created
            return HostResult(
                host,
                true,
                dir_created ? "rsync ok (created remote dir)" : "rsync ok",
            )
        catch e
            msg = sprint(showerror, e)
            if dir_created
                msg = "rsync failed after creating directory: " * msg
            end
            return HostResult(host, false, msg)
        end
    end

    map_host_jobs(hosts) do i, host
        host_results[i] = _setup_host_call!(host) do
            _rsync_host_result(host)
        end
    end

    succeeded = 0
    failed = 0
    for hr in host_results
        if hr.ok
            succeeded += 1
        else
            failed += 1
        end
        if report && !sequential_spin
            kit_print("  $(hr.host): ")
            if hr.ok
                print_ok("✓")
                kit_println()
            else
                print_err("✗ $(hr.message)")
                println()
            end
        elseif report && sequential_spin && !hr.ok
            print_err("✗ $(hr.message)")
            println()
        elseif report && sequential_spin && hr.ok
            print_ok("✓")
            kit_println()
        end
    end

    if confirm
        kit_println()
        writeln_both("Reminder: local/remote git commits are not tracked by this operation.")
        writeln_both(
            "`drive` runs without git parity by default; use --require-git only on git remotes.",
        )
    end

    return (
        cancelled=false,
        succeeded=succeeded,
        failed=failed,
        host_results=host_results,
    )
end
