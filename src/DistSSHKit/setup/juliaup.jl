# Align remote Julia via juliaup (`setup --juliaup` / check Fix hints).

"""Remote juliaup binary (non-interactive SSH has no login PATH)."""
const _JULIAUP_REMOTE_BIN = raw"$HOME/.juliaup/bin/juliaup"

"""Channel string for juliaup from a Julia `VersionNumber` (`\"1.12\"`)."""
juliaup_channel(v::VersionNumber=VERSION)::String = "$(v.major).$(v.minor)"

"""SSH body: add / update / default `channel` with remote juliaup."""
function _juliaup_align_remote_sh(channel::AbstractString)::String
    ch = String(channel)
    cq = _remote_sh_quote(ch)
    return """
JU=$(_JULIAUP_REMOTE_BIN)
if [ ! -x \"\$JU\" ]; then
  echo \"juliaup not found at \$HOME/.juliaup/bin/juliaup\" >&2
  exit 127
fi
if ! \"\$JU\" add $cq; then
  if ! \"\$JU\" status 2>/dev/null | grep -F -q $cq; then
    printf 'juliaup add %s failed\\n' $cq >&2
    exit 1
  fi
fi
\"\$JU\" update $cq || exit \$?
\"\$JU\" default $cq || exit \$?
echo ok
"""
end

"""Print Fix lines for missing / mismatched remote Julia (check output)."""
function print_juliaup_align_fix!(
    host::AbstractString;
    kind::Symbol=:mismatch,
    channel::AbstractString=juliaup_channel(),
)
    ch = String(channel)
    h = String(host)
    kit_println("    Fix: julia --project=. -m DistSSHKit setup --juliaup $h")
    kit_println("         (or on $h: $(_JULIAUP_REMOTE_BIN) add $ch && \\")
    kit_println("          $(_JULIAUP_REMOTE_BIN) update $ch && \\")
    kit_println("          $(_JULIAUP_REMOTE_BIN) default $ch -- changes host default Julia)")
    kit_println("         No juliaup? install it first (see Requirements), or use --julia PATH /")
    kit_println("         JULIA_DISTRIBUTED_EXE.")
    if kind === :mismatch
        kit_println("         Or pass --ignore-julia-version to continue anyway.")
    end
    return nothing
end

"""True when `remote` is same major.minor as `local` but a newer VersionNumber."""
function juliaup_controller_behind_channel(
    local_version::VersionNumber,
    remote_version::VersionNumber,
)::Bool
    julia_version_mismatch_kind(local_version, remote_version) == :minor && return false
    return remote_version > local_version
end

"""Note when remotes landed on a newer patch than the controller (channel latest)."""
function print_juliaup_controller_patch_note!(
    remote_version::VersionNumber;
    local_version::VersionNumber=VERSION,
    channel::AbstractString=juliaup_channel(local_version),
)
    juliaup_controller_behind_channel(local_version, remote_version) || return false
    ch = String(channel)
    warn("controller Julia $local_version is behind channel $ch latest on remotes ($remote_version)")
    kit_println("    Tip: update the controller (e.g. juliaup update $ch), then re-run workers.")
    return true
end

"""Parse remote Julia version via setup SSH transport (`DISTSSHKIT_TEST_SSH`)."""
function _remote_julia_version_setup_ssh(
    host::AbstractString,
    julia_path::AbstractString,
)::Union{Nothing,VersionNumber}
    pq = _remote_shell_path_word(String(julia_path))
    try
        out = read(
            pipeline(_host_sync_remote_shell_cmd(String(host), "$pq --version"); stderr=devnull),
            String,
        )
        return parse_julia_version(out)
    catch
        return nothing
    end
end

"""
Align each host's juliaup default to `channel` (controller major.minor).

Requires existing `\$HOME/.juliaup/bin/juliaup` on the remote (does not install
juliaup). Runs `add` → `update` → `default`. Confirm unless `confirm=false`.
"""
function juliaup_align_remotes(
    hosts::Vector{String};
    channel::AbstractString=juliaup_channel(),
    confirm::Bool=true,
)::NamedTuple
    ch = String(channel)
    if confirm && !kit_noninteractive()
        print_err("  This will run juliaup add/update/default $ch on each host.\n")
        println_fatal("  That changes the host default Julia (\$HOME/.juliaup/bin/julia).")
        println_fatal("  Hosts: $(join(hosts, ", "))")
        println_fatal("  juliaup must already exist at \$HOME/.juliaup/bin/juliaup.")
        println_fatal()
        kit_confirm("Type 'juliaup' to confirm: "; keyword="juliaup") || begin
            println_fatal("Cancelled.")
            return (; cancelled=true, succeeded=0, failed=0, hosts=HostResult[])
        end
        println_fatal()
    end

    remote_sh = _juliaup_align_remote_sh(ch)
    succeeded = 0
    failed = 0
    host_results = HostResult[]
    for host in hosts
        _setup_host_span!(host, :running)
        err_buf = IOBuffer()
        out_buf = IOBuffer()
        try
            kit_spin!("  $host: ") do
                proc = run(
                    pipeline(
                        ignorestatus(_host_sync_remote_shell_cmd(host, remote_sh));
                        stdout=out_buf,
                        stderr=err_buf,
                    );
                    wait=true,
                )
                if proc.exitcode != 0
                    msg = strip(String(take!(err_buf)))
                    isempty(msg) && (msg = strip(String(take!(out_buf))))
                    isempty(msg) && (msg = "juliaup align exit $(proc.exitcode)")
                    error(first(split(msg, '\n')))
                end
                return nothing
            end
            clear_detect_julia_path_cache!(host)
            path = detect_julia_path(host)
            path === nothing && error("Julia not found after juliaup align")
            ver = _remote_julia_version_setup_ssh(host, path)
            ver === nothing && error("Julia --version unparseable after juliaup align")
            if julia_version_mismatch_kind(VERSION, ver) == :minor
                error("still mismatched after align: local $(VERSION), remote $ver")
            end
            print_ok("✓ Julia $ver (channel $ch)")
            kit_println()
            print_juliaup_controller_patch_note!(ver; channel=ch)
            succeeded += 1
            push!(host_results, HostResult(host, true, "juliaup $ch"))
            _setup_host_span!(host, :ok)
        catch e
            detail = strip(String(take!(err_buf)))
            report_remote_failure(e; stderr=detail)
            combined = isempty(detail) ? sprint(showerror, e) : detail
            if occursin("juliaup not found", combined) || occursin("127", combined)
                kit_println("    Install juliaup on $host first (see Requirements), then retry.")
            end
            failed += 1
            push!(host_results, HostResult(host, false, combined))
            _setup_host_span!(host, :fail)
        end
    end
    return (; host_op_result(succeeded=succeeded, failed=failed)..., hosts=host_results)
end
