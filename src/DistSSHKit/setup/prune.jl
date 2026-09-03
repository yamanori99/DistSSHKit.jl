# Prune `.distsshkit/{go,drive,setup}` leaves without wiping the deploy tree.

"""Remove matching kit leaf dirs under `root`. Returns the number removed."""
function prune_kit_leaf_dirs!(
    root::AbstractString;
    older_days::Union{Nothing,Integer}=nothing,
    id::Union{Nothing,AbstractString}=nothing,
    skip_setup::Union{Nothing,AbstractString}=nothing,
)::Int
    isdir(root) || return 0
    idn = id === nothing ? nothing : String(id)
    skip = skip_setup === nothing ? nothing : realpath(String(skip_setup))
    victims = String[]
    for (dir, _, _) in walkdir(String(root); onerror=Returns(nothing))
        basename(dir) == ".distsshkit" || continue
        go = joinpath(dir, "go")
        if isdir(go)
            for child in readdir(go; join=true)
                isdir(child) || continue
                _prune_id_ok(basename(child), idn) || continue
                _prune_age_ok(child, older_days) || continue
                push!(victims, child)
            end
        end
        if idn === nothing
            for kind in ("drive", "setup")
                p = joinpath(dir, kind)
                isdir(p) || continue
                if kind == "setup" && skip !== nothing && isdir(p) &&
                   realpath(p) == skip
                    continue
                end
                _prune_age_ok(p, older_days) || continue
                push!(victims, p)
            end
        end
    end
    n = 0
    for p in victims
        isdir(p) || continue
        rm(p; recursive=true, force=true)
        n += 1
    end
    return n
end

function _prune_id_ok(name::AbstractString, id::Union{Nothing,String})::Bool
    id === nothing && return true
    return occursin(id, String(name))
end

function _prune_age_ok(path::AbstractString, older_days::Union{Nothing,Integer})::Bool
    older_days === nothing && return true
    return (time() - mtime(path)) >= Float64(older_days) * 86400
end

"""
Prune kit run leaves on localhost (`project`) and SSH hosts (`remote_path`).

Does not delete the project tree. Confirm unless `confirm=false`.
"""
function prune_kit_leaves(
    hosts::Vector{String},
    remote_path::AbstractString,
    project::AbstractString;
    confirm::Bool=true,
    older_days::Union{Nothing,Integer}=nothing,
    id::Union{Nothing,AbstractString}=nothing,
    skip_setup::Union{Nothing,AbstractString}=nothing,
)::NamedTuple
    if confirm && !kit_noninteractive()
        print_err("  This will DELETE .distsshkit go/drive/setup leaves.\n")
        println_fatal("  Local project: $project")
        println_fatal("  Remote path: $remote_path")
        println_fatal("  Hosts: $(join(hosts, ", "))")
        older_days !== nothing && println_fatal("  older-than: $older_days day(s)")
        id !== nothing && println_fatal("  id: $id")
        println_fatal("  Deploy tree and output/ are left alone.")
        println_fatal()
        kit_confirm("Type 'prune' to confirm: "; keyword="prune") || begin
            println_fatal("Cancelled.")
            return (; cancelled=true, succeeded=0, failed=0, hosts=HostResult[])
        end
        println_fatal()
    end

    kit_spin!("  localhost: ") do
        prune_kit_leaf_dirs!(
            project;
            older_days=older_days,
            id=id,
            skip_setup=skip_setup,
        )
        return nothing
    end
    print_ok("✓")
    kit_println()

    cmd = _prune_remote_shell(remote_path; older_days=older_days, id=id)
    succeeded = 0
    failed = 0
    host_results = HostResult[]
    for host in hosts
        _setup_host_span!(host, :running)
        err_buf = IOBuffer()
        try
            kit_spin!("  $host: ") do
                read(pipeline(_host_sync_remote_shell_cmd(host, cmd); stderr=err_buf), String)
                return nothing
            end
            print_ok("✓")
            kit_println()
            succeeded += 1
            push!(host_results, HostResult(host, true, "pruned"))
            _setup_host_span!(host, :ok)
        catch e
            detail = strip(String(take!(err_buf)))
            report_remote_failure(e; stderr=detail)
            failed += 1
            msg = isempty(detail) ? sprint(showerror, e) : detail
            push!(host_results, HostResult(host, false, msg))
            _setup_host_span!(host, :fail)
        end
    end
    return (; host_op_result(succeeded=succeeded, failed=failed)..., hosts=host_results)
end

function _prune_remote_shell(
    remote_path::AbstractString;
    older_days::Union{Nothing,Integer}=nothing,
    id::Union{Nothing,AbstractString}=nothing,
)::String
    pq = _remote_shell_path_word(remote_path)
    older = older_days === nothing ? "" : string(Int(older_days))
    idn = id === nothing ? "" : String(id)
    idq = Base.shell_escape(idn)
    older_q = Base.shell_escape(older)
    return """
        # DISTSSHKIT_PRUNE_KIT_LEAVES
        root=$pq
        older=$older_q
        id=$idq
        [ -d "\$root" ] || exit 0
        find "\$root" -type d -name .distsshkit 2>/dev/null | while IFS= read -r kit; do
          go="\$kit/go"
          if [ -d "\$go" ]; then
            for child in "\$go"/*; do
              [ -d "\$child" ] || continue
              base=\$(basename "\$child")
              if [ -n "\$id" ]; then
                case "\$base" in *"\$id"*) ;; *) continue ;; esac
              fi
              if [ -n "\$older" ] && [ "\$older" != 0 ]; then
                # find -mtime +N is > N days; local prune is >= DAYS.
                [ -n "\$(find "\$child" -maxdepth 0 -mtime +"\$((older - 1))" 2>/dev/null)" ] || continue
              fi
              rm -rf "\$child"
            done
          fi
          if [ -z "\$id" ]; then
            for kind in drive setup; do
              p="\$kit/\$kind"
              [ -d "\$p" ] || continue
              if [ -n "\$older" ] && [ "\$older" != 0 ]; then
                [ -n "\$(find "\$p" -maxdepth 0 -mtime +"\$((older - 1))" 2>/dev/null)" ] || continue
              fi
              rm -rf "\$p"
            done
          fi
        done
        """
end
