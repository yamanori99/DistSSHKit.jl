# Git push/pull sync to SSH hosts (shared by `setup --sync` / `--pull` and `sync!`).

function git_push_project!(project::AbstractString)::Bool
    cmd = _git_cmd(["-C", String(project), "push"])
    try
        run(pipeline(cmd, stdout=devnull, stderr=devnull))
        return true
    catch e
        _rethrow_missing_host_tool(e)
        return false
    end
end

function git_pull_local_project!(project::AbstractString)::Bool
    cmd = _git_cmd(["-C", String(project), "pull"])
    try
        run(pipeline(cmd, stdout=devnull, stderr=devnull))
        return true
    catch e
        _rethrow_missing_host_tool(e)
        return false
    end
end

"""Remote login-shell snippet for `git pull` at `remote_path`."""
function _git_pull_remote_inner(remote_path::AbstractString)::String
    return "cd $(_remote_shell_path_word(remote_path)) && git pull"
end

function git_pull_remote_host!(host::AbstractString, remote_path::AbstractString)::Bool
    cmd = _git_pull_remote_inner(remote_path)
    try
        run(pipeline(_ssh_cmd([ssh_opts()..., String(host), cmd]), stdout=devnull, stderr=devnull))
        return true
    catch e
        _rethrow_missing_host_tool(e)
        return false
    end
end

function _git_remote_url(project::AbstractString)::String
    try
        return strip(read(pipeline(_git_cmd(["-C", String(project), "remote", "get-url", "origin"]); stderr=devnull), String))
    catch e
        _rethrow_missing_host_tool(e)
        return "<repo_url>"
    end
end

function _print_git_sync_banner!(
    hosts::Vector{String},
    project::AbstractString,
    remote_path::AbstractString;
    do_push::Bool,
    do_pull::Bool,
    do_local_pull::Bool,
)
    # Consent text: always on the terminal (same gate as `kit_confirm`).
    println_fatal("  Repository: $(_git_remote_url(project))")
    println_fatal("  Remote path: $remote_path")
    println_fatal("  Hosts: $(join(hosts, ", "))")
    println_fatal()
    println_fatal("  This will:")
    do_local_pull && println_fatal("    git pull on localhost")
    if do_push
        print_warn("    git push (local → origin; not only the listed hosts)\n")
    end
    do_pull && println_fatal("    git pull on remotes")
    println_fatal()
    return nothing
end

"""
    git_sync_project_to_hosts!(
        hosts, project, remote_path;
        do_push=true, do_pull=true, do_local_pull=false, confirm=true,
    ) -> (; ok, cancelled, host_results)

Push/pull git so remotes match `project`. Used by `setup --sync` / `--pull` and
[`sync!`](@ref) (`mode=:sync`).

When `confirm=true`, prints the planned git steps and requires `y` (unless
[`kit_noninteractive`](@ref) / `--yes` is active).
"""
function git_sync_project_to_hosts!(
    hosts::Vector{String},
    project::AbstractString,
    remote_path::AbstractString;
    do_push::Bool=true,
    do_pull::Bool=true,
    do_local_pull::Bool=false,
    confirm::Bool=true,
)
    proj = canonical_local_path(project)
    remote = String(remote_path)
    host_results = HostResult[]

    if confirm && !kit_noninteractive()
        _print_git_sync_banner!(
            hosts, proj, remote;
            do_push=do_push, do_pull=do_pull, do_local_pull=do_local_pull,
        )
        kit_confirm("Proceed? [y/N]: ") || begin
            println_fatal("Cancelled.")
            return (; ok=false, cancelled=true, host_results=HostResult[])
        end
        println_fatal()
    end

    if do_local_pull
        ok_local = kit_spin!("  localhost git pull: ") do
            git_pull_local_project!(proj)
        end
        if ok_local
            print_ok("✓")
            kit_println()
        else
            print_progress_err("✗")
            kit_println()
            return (; ok=false, cancelled=false, host_results=host_results)
        end
    end

    if do_push
        ok_push = kit_spin!("  git push: ") do
            git_push_project!(proj)
        end
        if ok_push
            print_ok("✓")
            kit_println()
        else
            print_err("✗")
            println_fatal()
            println_fatal()
            repo_url = _git_remote_url(proj)
            print_warn("Push failed.\n")
            println_fatal()
            println_fatal("  Remote: $repo_url")
            println_fatal()
            println_fatal("  Not a team member?")
            println_fatal("    Use --pull instead (fork not needed for experiments)")
            println_fatal()
            println_fatal("  Team member?")
            println_fatal("    git pull --rebase && git push")
            return (; ok=false, cancelled=false, host_results=host_results)
        end
    end

    if do_pull
        for host in hosts
            ok_host = _setup_host_call!(host) do
                kit_spin!("  $host git pull: ") do
                    git_pull_remote_host!(host, remote)
                end
            end
            if ok_host
                print_ok("✓")
                kit_println()
                push!(host_results, HostResult(host, true, "git pull ok"))
            else
                print_progress_err("✗")
                kit_println()
                push!(host_results, HostResult(host, false, "git pull failed"))
                return (; ok=false, cancelled=false, host_results=host_results)
            end
        end
    end

    kit_println()
    return (; ok=true, cancelled=false, host_results=host_results)
end
