# Git push/pull sync to SSH hosts (shared by `setup --sync` / `--pull` and `sync!`).

function git_push_project!(project::AbstractString)::Bool
    try
        run(pipeline(`git -C $(String(project)) push`, stdout=devnull, stderr=devnull))
        return true
    catch
        return false
    end
end

function git_pull_local_project!(project::AbstractString)::Bool
    try
        run(pipeline(`git -C $(String(project)) pull`, stdout=devnull, stderr=devnull))
        return true
    catch
        return false
    end
end

function git_pull_remote_host!(host::AbstractString, remote_path::AbstractString)::Bool
    cmd = "cd $(String(remote_path)) && git pull"
    try
        run(pipeline(Cmd(["ssh", ssh_opts()..., String(host), cmd]), stdout=devnull, stderr=devnull))
        return true
    catch
        return false
    end
end

function _git_remote_url(project::AbstractString)::String
    try
        return strip(read(`git -C $(String(project)) remote get-url origin`, String))
    catch
        return "<repo_url>"
    end
end

"""
    git_sync_project_to_hosts!(
        hosts, project, remote_path;
        do_push=true, do_pull=true, do_local_pull=false,
    ) -> (; ok, host_results)

Push/pull git so remotes match `project`. Used by `setup --sync` / `--pull` and
[`sync!`](@ref) (`mode=:sync`).
"""
function git_sync_project_to_hosts!(
    hosts::Vector{String},
    project::AbstractString,
    remote_path::AbstractString;
    do_push::Bool=true,
    do_pull::Bool=true,
    do_local_pull::Bool=false,
)
    proj = canonical_local_path(project)
    remote = String(remote_path)
    host_results = HostResult[]

    if do_local_pull
        kit_print("  localhost git pull: ")
        if git_pull_local_project!(proj)
            print_ok("✓")
            kit_println()
        else
            print_progress_err("✗")
            kit_println()
            return (; ok=false, host_results=host_results)
        end
    end

    if do_push
        kit_print("  git push: ")
        if git_push_project!(proj)
            print_ok("✓")
            kit_println()
        else
            print_progress_err("✗")
            kit_println()
            kit_println()
            repo_url = _git_remote_url(proj)
            print_progress_warn("Push failed.")
            kit_println()
            kit_println()
            kit_println("  Remote: $repo_url")
            kit_println()
            kit_println("  Not a team member?")
            kit_println("    Use --pull instead (fork not needed for experiments)")
            kit_println()
            kit_println("  Team member?")
            kit_println("    git pull --rebase && git push")
            return (; ok=false, host_results=host_results)
        end
    end

    if do_pull
        for host in hosts
            kit_print("  $host git pull: ")
            if git_pull_remote_host!(host, remote)
                print_ok("✓")
                kit_println()
                push!(host_results, HostResult(host, true, "git pull ok"))
            else
                print_progress_err("✗")
                kit_println()
                push!(host_results, HostResult(host, false, "git pull failed"))
                return (; ok=false, host_results=host_results)
            end
        end
    end

    kit_println()
    return (; ok=true, host_results=host_results)
end
