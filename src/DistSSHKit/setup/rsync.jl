# Rsync local project tree to SSH hosts (shared by `setup --rsync` and `sync!`).

function _host_sync_rsync_transport()::String
    custom = strip(get(ENV, "DISTSSHKIT_TEST_SSH", ""))
    if !isempty(custom)
        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        path = abspath(custom)
        return join([julia, "--startup-file=no", path], " ")
    end
    return "ssh " * join(ssh_opts(), " ")
end

function _host_sync_rsync_argv()::Vector{String}
    custom = strip(get(ENV, "DISTSSHKIT_TEST_RSYNC", ""))
    if !isempty(custom)
        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        path = abspath(custom)
        return [julia, "--startup-file=no", path]
    end
    return ["rsync"]
end

function _host_sync_remote_shell_cmd(host::String, remote_script::String)::Cmd
    custom = strip(get(ENV, "DISTSSHKIT_TEST_SSH", ""))
    if !isempty(custom)
        julia = joinpath(Sys.BINDIR, Base.julia_exename())
        path = abspath(custom)
        return Cmd([julia, "--startup-file=no", path, host, remote_script])
    end
    return Cmd(vcat(["ssh"], collect(ssh_opts()), [host, remote_script]))
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
    catch
        return false
    end
end

function _print_rsync_safety_banner!(
    local_root::AbstractString,
    remote_path::AbstractString,
    hosts::Vector{String},
    path_anchor::AbstractString,
)
    # Banner is detail-only; quiet/progress leave the TTY (and skip this noise).
    !kit_output_detail() && return nothing
    kit_print("  ")
    print_progress_warn("This bypasses git entirely: no commit, no push/pull, no hash check.")
    kit_println()
    kit_println("  Local and remote git commits will likely disagree afterwards.")
    kit_println("  That is fine: `drive` does not require git parity by default.")
    kit_println("  Use `drive --require-git` only with git-managed remotes.")
    kit_println("  Prefer `setup --sync` when you need the git-commit reproducibility guarantee.")
    kit_println()
    kit_print("  ")
    print_progress_warn("Safety: refuses if the remote path already has any files.")
    kit_println()
    kit_println("  To replace an existing tree, run `setup --delete` first, then `--rsync`.")
    kit_println("  Mirrors onto a missing/empty path (`--delete`); excludes `.git/`; honors `.gitignore`.")
    kit_println()
    kit_println("  Local project: $(display_path(local_root, path_anchor))")
    kit_println("  Remote path: $remote_path")
    kit_println("  Hosts: $(join(hosts, ", "))")
    kit_println()
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

    if confirm
        _print_rsync_safety_banner!(local_root, remote_path, hosts, path_anchor)
        if !kit_noninteractive()
            if !kit_confirm("Type 'rsync' to confirm: "; keyword="rsync")
                kit_println("Cancelled.")
                return (
                    cancelled=true,
                    succeeded=0,
                    failed=0,
                    host_results=HostResult[],
                )
            end
            kit_println()
        end
    end

    ssh_cmd_str = _host_sync_rsync_transport()
    host_results = HostResult[]
    succeeded = 0
    failed = 0
    for host in hosts
        dir_created = false
        try
            outcome = if report
                kit_spin!("  $host: ") do
                    _rsync_one_host!(
                        host, local_root, remote_path, ssh_cmd_str;
                    )
                end
            else
                _rsync_one_host!(host, local_root, remote_path, ssh_cmd_str)
            end
            if outcome.status === :busy || outcome.status === :mkdir_fail
                if report
                    print_progress_err("✗ $(outcome.message)")
                    kit_println()
                end
                push!(host_results, HostResult(host, false, outcome.message))
                failed += 1
                continue
            end
            dir_created = outcome.dir_created
            if report
                print_ok("✓")
                kit_println()
            end
            push!(
                host_results,
                HostResult(host, true, dir_created ? "rsync ok (created remote dir)" : "rsync ok"),
            )
            succeeded += 1
        catch e
            msg = sprint(showerror, e)
            if dir_created
                msg = "rsync failed after creating directory: " * msg
            end
            if report
                if dir_created
                    print_progress_err("✗ rsync failed after creating directory: $(sprint(showerror, e))")
                else
                    print_progress_err("✗ $(sprint(showerror, e))")
                end
                kit_println()
            end
            push!(host_results, HostResult(host, false, msg))
            failed += 1
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
