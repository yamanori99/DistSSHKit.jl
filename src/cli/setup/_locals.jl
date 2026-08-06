# Local project-root accessors for setup CLI.
# JETLS may analyze `src/cli/setup/*.jl` as leaf files without loading `setup.jl` first.

function _setup_local_root()::String
    kit_src = joinpath(@__DIR__, "..")
    if isdefined(@__MODULE__, :cli_project_root)
        return String(cli_project_root(kit_src))
    end
    return String(DistSSHKit.kit_project_root(kit_src))
end

function _setup_path_anchor()::String
    root = _setup_local_root()
    if isdefined(@__MODULE__, :DistSSHKit)
        return DistSSHKit.canonical_local_path(root)
    end
    return abspath(root)
end
