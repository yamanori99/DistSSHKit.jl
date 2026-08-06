# Loaded once from drive.jl before other drive/*.jl fragments.
# Do not `include` DistSSHKit here — that duplicates `drive.jl` and triggers IDE DuplicateInclude.
using Dates
using Distributed

"""Build a drive error when the driver script path does not exist."""
function drive_script_not_found_message(script_path::AbstractString, project_root::AbstractString)::String
    path = String(script_path)
    root = String(project_root)
    msg = "Script not found: $path"
    base = basename(path)
    if endswith(base, ".jl")
        for group in ("with_kit", "without_kit")
            bundled = joinpath(root, "demos", group, base)
            if isfile(bundled)
                return msg * "\nHint: run `julia --project=. -m DistSSHKit demo install` to copy demos into ./demos/, or use demos/$group/$base"
            end
        end
    end
    return msg
end
