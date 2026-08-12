# Loaded once from drive.jl before other drive/*.jl fragments.
# Do not `include` DistSSHKit here — that duplicates `drive.jl` and triggers IDE DuplicateInclude.
using Dates
using Distributed

"""Build a drive error when the driver script path does not exist."""
function drive_script_not_found_message(
    script_path::AbstractString,
    project_root::AbstractString;
    surface::Symbol=:cli,
)::String
    return DistSSHKit.explain_script_not_found(script_path, project_root; surface=surface)
end
