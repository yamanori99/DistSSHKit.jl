# Setup host validation, SSH preflight, and multi-host result reporting.

"""Outcome of a multi-host setup op (`delete` / `clone` / `instantiate` / …)."""
host_op_result(; cancelled::Bool=false, succeeded::Int=0, failed::Int=0) =
    (; cancelled, succeeded, failed)

"""
Validate setup CLI hosts.

Setup hosts are **SSH targets only**. Unlike `drive` / `go`, `masterhost` is not
an SSH target — pass `user@host` (or an SSH config `Host` alias).
"""
function validate_setup_hosts(hosts::AbstractVector{<:AbstractString})
    isempty(hosts) && throw(ArgumentError("No hosts specified"))
    for raw in hosts
        host = String(raw)
        if is_local_host_name(host)
            throw(ArgumentError(
                "setup hosts are SSH targets only; $(repr(host)) means this job's DistSSHKit parent in drive/go. " *
                "Pass user@host (or an SSH config Host alias). " *
                "To remove a local project tree, delete it on this machine yourself.",
            ))
        end
        if looks_like_path_host(host)
            throw(ArgumentError(
                "refusing path-like host $(repr(host)); setup expects SSH hosts " *
                "(user@host or config alias), not a local script/path. " *
                "Put SCRIPT.jl after hosts for drive/go, not for setup.",
            ))
        end
        isempty(strip(host)) && throw(ArgumentError("empty host name"))
    end
    return nothing
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
