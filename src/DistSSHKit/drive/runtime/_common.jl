# Loaded once from DistSSHKit.jl before other drive/runtime fragments.
using Dates
using Distributed

"""Build a drive error when the driver script path does not exist."""
function drive_script_not_found_message(
        script_path::AbstractString,
        project_root::AbstractString;
        surface::Symbol = :cli,
    )::String
    return explain_script_not_found(script_path, project_root; surface = surface)
end
