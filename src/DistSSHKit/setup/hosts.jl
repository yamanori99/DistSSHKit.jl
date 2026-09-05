# Setup host validation, SSH preflight, and multi-host result reporting.

"""Outcome of a multi-host setup op (`delete` / `clone` / `instantiate` / …)."""
host_op_result(; cancelled::Bool=false, succeeded::Int=0, failed::Int=0) =
    (; cancelled, succeeded, failed)

"""
Validate normalized setup hosts (SSH names after CLI placement parse).

CLI entry is the same vocabulary as go / drive / size (`parent[:N]` /
`child:NAME[:N]`; `:N` ignored). After parse, this checks the stripped
names. `setup --juliaup` also accepts [`PARENT_HOST_NAME`](@ref) when
`allow_parent=true`.
"""
function validate_setup_hosts(
    hosts::AbstractVector{<:AbstractString};
    allow_parent::Bool=false,
)
    isempty(hosts) && throw(ArgumentError("No hosts specified"))
    for raw in hosts
        host = String(raw)
        throw_legacy_placement_token(host)
        if is_parent_host_name(host)
            allow_parent || throw(ArgumentError(
                "setup: $(repr(host)) is only for --juliaup (kit parent machine). " *
                "SSH targets use `child:NAME` (or `child:NAME:N`; `:N` ignored).",
            ))
            continue
        end
        if looks_like_path_host(host)
            throw(ArgumentError(
                "refusing path-like host $(repr(host)); setup expects `child:NAME` " *
                "(SSH host or config alias), not a local script/path. " *
                "Put SCRIPT.jl after hosts for drive/go, not for setup.",
            ))
        end
        isempty(strip(host)) && throw(ArgumentError("empty host name"))
    end
    return nothing
end

"""CLI token for a normalized setup host (Fix / Tip copy-paste)."""
function setup_cli_host_token(host::AbstractString)::String
    h = String(host)
    is_parent_host_name(h) && return PARENT_HOST_NAME
    return format_placement_token(:child, h)
end

"""SSH names from a juliaup target list (drops `parent`)."""
function setup_juliaup_ssh_hosts(hosts::AbstractVector{<:AbstractString})::Vector{String}
    return String[String(h) for h in hosts if !is_parent_host_name(h)]
end

"""
Probe one host via the setup SSH transport (honors `DISTSSHKIT_TEST_SSH`).

Returns `nothing` on success, or a short error summary string on failure.
"""
function probe_setup_ssh(host::String)::Union{Nothing,String}
    err_buf = IOBuffer()
    try
        out = read(
            pipeline(_host_sync_remote_shell_cmd(host, "echo ok"); stderr=err_buf),
            String,
        )
        strip(out) == "ok" && return nothing
        detail = strip(String(take!(err_buf)))
        note = isempty(detail) ? "unexpected SSH output: $(repr(strip(out)))" : detail
        return _truncate_ssh_message(note)
    catch e
        e isa ArgumentError && return sprint(showerror, e)
        return summarize_ssh_error(e; stderr=String(take!(err_buf)))
    end
end

"""
Probe SSH to each host via the setup SSH transport.

Returns `true` when every host answers. Prints a short summary per failure.
"""
function preflight_setup_ssh(hosts::Vector{String})::Bool
    kit_println("SSH preflight:")
    all_ok = true
    for host in hosts
        kit_print("  $host: ")
        flush(stdout)
        err = probe_setup_ssh(host)
        if err === nothing
            print_ok("✓")
            kit_println()
        else
            all_ok = false
            print_progress_err("✗")
            kit_println()
            kit_println("    $err")
        end
    end
    kit_println()
    return all_ok
end

"""
Print final status for a multi-host op. Returns `true` on success.

Cancelled ops return `true` without printing a success line (caller already said so).
"""
function finish_host_op!(label::AbstractString, result)::Bool
    result.cancelled && return true
    kit_println()
    if result.succeeded == 0
        print_err("$label did not succeed on any host.")
        kit_println()
        kit_println("    Fix: ssh -o BatchMode=yes -o ConnectTimeout=5 HOST echo ok")
        kit_println()
        return false
    end
    if result.failed > 0
        print_err("$label failed on $(result.failed) host(s) ($(result.succeeded) ok).")
        kit_println()
        kit_println()
        return false
    end
    print_ok("$label complete ($(result.succeeded) host(s)).")
    kit_println()
    kit_println()
    return true
end

"""Print a remote-op failure line using [`summarize_ssh_error`](@ref)."""
function report_remote_failure(err; stderr::AbstractString="")
    print_progress_err("✗")
    kit_println()
    kit_println("    $(summarize_ssh_error(err; stderr=stderr))")
    return nothing
end
