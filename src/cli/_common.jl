# Shared helpers for kit CLI scripts (`cli/*.jl`).
# Included once from each `src/cli/*/_using.jl`.

if !isdefined(@__MODULE__, :cli_project_root)
    """Resolve local project root for kit CLI scripts."""
    function cli_project_root(kit_src_dir::AbstractString)
        get(ENV, "DISTRIBUTED_PROJECT_ROOT") do
            DistSSHKit.kit_project_root(kit_src_dir)
        end
    end

    """Short label for the local project root in console output."""
    function cli_project_disp(
        project_root::AbstractString,
        path_anchor::AbstractString=DistSSHKit.canonical_local_path(project_root),
    )::String
        return DistSSHKit.cli_project_disp(project_root, path_anchor)
    end
end
