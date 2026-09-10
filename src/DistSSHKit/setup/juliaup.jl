# Align remote Julia via juliaup (`setup --juliaup` / check Fix hints).

"""Official install path for remote juliaup (non-interactive SSH has no login PATH)."""
const _JULIAUP_REMOTE_BIN_HOME = raw"$HOME/.juliaup/bin/juliaup"

"""
Ordered remote `juliaup` candidates (same preference as Julia binaries).

Prefers the official install under `\$HOME/.juliaup`, then Homebrew on macOS
(`/opt/homebrew`, `/usr/local`). Linux only needs the home install today.
"""
function remote_juliaup_candidates(uname_s::AbstractString)::Vector{String}
    os = lowercase(strip(String(uname_s)))
    home = _JULIAUP_REMOTE_BIN_HOME
    if startswith(os, "darwin")
        return String[home, "/opt/homebrew/bin/juliaup", "/usr/local/bin/juliaup"]
    end
    return String[home]
end

"""Candidates when remote OS is unknown: try home + Homebrew paths."""
function remote_juliaup_candidates()::Vector{String}
    return String[
        _JULIAUP_REMOTE_BIN_HOME,
        "/opt/homebrew/bin/juliaup",
        "/usr/local/bin/juliaup",
    ]
end

"""Shell word for a juliaup candidate (`\$HOME/...` expands on the remote)."""
function _juliaup_candidate_sh_word(path::AbstractString)::String
    p = String(path)
    p == _JULIAUP_REMOTE_BIN_HOME && return "\"\$HOME/.juliaup/bin/juliaup\""
    return p
end

"""Channel string for juliaup from a Julia `VersionNumber` (`\"1.12\"`)."""
juliaup_channel(v::VersionNumber = VERSION)::String = "$(v.major).$(v.minor)"

"""SSH body: add / update / default `channel` with remote juliaup."""
function _juliaup_align_remote_sh(
        channel::AbstractString;
        candidates::Vector{String} = remote_juliaup_candidates(),
    )::String
    ch = String(channel)
    cq = _remote_sh_quote(ch)
    words = join(_juliaup_candidate_sh_word.(candidates), " ")
    tried = join(candidates, ", ")
    return """
    JU=\"\"
    for c in $words; do
      if [ -x \"\$c\" ]; then
        JU=\"\$c\"
        break
      fi
    done
    if [ -z \"\$JU\" ]; then
      echo \"juliaup not found (tried: $tried)\" >&2
      exit 127
    fi
    default=\$( \"\$JU\" status 2>/dev/null | awk '\$1==\"*\" { print \$2; exit }' )
    if [ \"\$default\" = $cq ]; then
      echo already
      exit 0
    fi
    if ! \"\$JU\" add $cq; then
      if ! \"\$JU\" status 2>/dev/null | grep -F -q $cq; then
        # `$cq` (not raw `$ch`): channel may come from the API; keep it shell-safe.
        printf 'juliaup add %s failed\\n' $cq >&2
        exit 1
      fi
    fi
    \"\$JU\" update $cq || exit \$?
    \"\$JU\" default $cq || exit \$?
    echo ok
    """
end

"""SSH body: `juliaup update` (all installed channels; does not `default`)."""
function _juliaup_update_remote_sh(
        candidates::Vector{String} = remote_juliaup_candidates(),
    )::String
    words = join(_juliaup_candidate_sh_word.(candidates), " ")
    tried = join(candidates, ", ")
    return """
    JU=\"\"
    for c in $words; do
      if [ -x \"\$c\" ]; then
        JU=\"\$c\"
        break
      fi
    done
    if [ -z \"\$JU\" ]; then
      echo \"juliaup not found (tried: $tried)\" >&2
      exit 127
    fi
    \"\$JU\" update || exit \$?
    echo ok
    """
end

"""Print Fix lines for missing / mismatched remote Julia (check output)."""
function print_juliaup_align_fix!(
        host::AbstractString;
        kind::Symbol = :mismatch,
        channel::AbstractString = juliaup_channel(),
    )
    ch = String(channel)
    h = String(host)
    kit_println("    Fix: julia --project=. -m DistSSHKit setup --juliaup $(setup_cli_host_token(h))")
    kit_println("         (or on $h: juliaup add $ch && juliaup update $ch && \\")
    kit_println("          juliaup default $ch —")
    kit_println("          \$HOME/.juliaup/bin/juliaup, /opt/homebrew/bin/juliaup,")
    kit_println("          or /usr/local/bin/juliaup; changes host default Julia)")
    kit_println("         No juliaup? install it first (see Requirements), or use --julia PATH /")
    kit_println("         JULIA_DISTRIBUTED_EXE.")
    if kind === :mismatch
        kit_println("         Or pass --ignore-julia-version to continue anyway.")
    end
    return nothing
end

"""True when `remote` is same major.minor as `local` but a newer VersionNumber."""
function juliaup_parent_behind_channel(
        local_version::VersionNumber,
        remote_version::VersionNumber,
    )::Bool
    julia_version_mismatch_kind(local_version, remote_version) == :minor && return false
    return remote_version > local_version
end

"""Note when remotes landed on a newer patch than the kit parent (channel latest)."""
function print_juliaup_parent_patch_note!(
        remote_version::VersionNumber;
        local_version::VersionNumber = VERSION,
        channel::AbstractString = juliaup_channel(local_version),
    )
    juliaup_parent_behind_channel(local_version, remote_version) || return false
    ch = String(channel)
    warn("kit parent Julia $local_version is behind channel $ch latest on remotes ($remote_version)")
    kit_println("    Tip: julia --project=. -m DistSSHKit setup --juliaup $PARENT_HOST_NAME")
    kit_println("         (or: juliaup update $ch && juliaup default $ch), then re-run workers.")
    return true
end

"""Local juliaup candidates (same layout as remotes; expands `\$HOME`)."""
function local_juliaup_candidates()::Vector{String}
    test = strip(get(ENV, "DISTSSHKIT_TEST_LOCAL_JULIAUP", ""))
    isempty(test) || return String[test]
    home = joinpath(homedir(), ".juliaup", "bin", "juliaup")
    if Sys.isapple()
        return String[home, "/opt/homebrew/bin/juliaup", "/usr/local/bin/juliaup"]
    end
    return String[home]
end

"""First existing local juliaup path, or `nothing`."""
function find_local_juliaup(
        candidates::Vector{String} = local_juliaup_candidates(),
    )::Union{Nothing, String}
    for c in candidates
        p = String(c)
        isfile(p) && return p
    end
    return nothing
end

"""Julia binary beside a local juliaup (official / Homebrew shim layout)."""
function _local_julia_beside_juliaup(juliaup_path::AbstractString)::String
    return joinpath(dirname(String(juliaup_path)), "julia")
end

"""Run local `juliaup` with stdout/stderr captured (live setup bar must not see it)."""
function _juliaup_run_captured(
        ju::AbstractString,
        args::AbstractVector{<:AbstractString},
    )
    out = IOBuffer()
    err = IOBuffer()
    cmd = Cmd(String[String(ju), String.(args)...])
    proc = run(pipeline(ignorestatus(cmd); stdout = out, stderr = err); wait = true)
    return proc, String(take!(out)), String(take!(err))
end

function _juliaup_captured_fail_msg(
        args::AbstractVector{<:AbstractString},
        proc,
        stdout_s::AbstractString,
        stderr_s::AbstractString,
    )::String
    msg = strip(String(stderr_s))
    isempty(msg) && (msg = strip(String(stdout_s)))
    isempty(msg) && (msg = "juliaup $(join(args, " ")) exit $(proc.exitcode)")
    return first(split(msg, '\n'))
end

"""Default juliaup channel from `juliaup status` (`*` row), or `nothing`."""
function _juliaup_default_channel_from_status(status_out::AbstractString)::Union{Nothing, String}
    for line in split(status_out, '\n'; keepempty = false)
        s = strip(line)
        isempty(s) && continue
        startswith(s, "Default") && continue
        startswith(s, "-") && continue
        m = match(r"^\*\s+(\S+)", s)
        m === nothing && continue
        cap = m.captures[1]
        cap isa AbstractString && return String(cap)
    end
    return nothing
end

"""When default channel and Julia version already match `channel`, return that version."""
function _juliaup_local_already_aligned(
        ju::AbstractString,
        channel::AbstractString,
    )::Union{Nothing, VersionNumber}
    ch = String(channel)
    proc, out, _ = _juliaup_run_captured(ju, ["status"])
    proc.exitcode == 0 || return nothing
    default_ch = _juliaup_default_channel_from_status(out)
    default_ch === nothing && return nothing
    default_ch == ch || return nothing
    jl = _local_julia_beside_juliaup(ju)
    isfile(jl) || return nothing
    ver = parse_julia_version(read(`$jl --version`, String))
    ver === nothing && return nothing
    julia_version_mismatch_kind(VERSION, ver) == :minor && return nothing
    return ver
end

"""One host line visible under `:progress` when juliaup is already on `channel`."""
function print_juliaup_already_on!(host::AbstractString, channel::AbstractString)
    msg = "  $(String(host)): already on $(String(channel))"
    with_kit_progress_suspended() do
        if kit_output_detail() || kit_output_progress()
            if kit_output_detail() && use_colors()
                printstyled(msg; color = :green)
                println()
            else
                println(msg)
            end
        end
    end
    _kit_log_writeln(msg)
    return nothing
end

"""Run local `juliaup add` / `update` / `default` for `channel`."""
function _juliaup_align_local!(
        channel::AbstractString;
        candidates::Vector{String} = local_juliaup_candidates(),
    )::NamedTuple
    ch = String(channel)
    ju = find_local_juliaup(candidates)
    ju === nothing && error(
        "juliaup not found (tried: $(join(candidates, ", ")))",
    )
    if (ver = _juliaup_local_already_aligned(ju, ch)) !== nothing
        return (; ver, changed = false)
    end
    add, add_out, add_err = _juliaup_run_captured(ju, ["add", ch])
    if add.exitcode != 0
        st = sprint() do io
            try
                run(pipeline(Cmd([ju, "status"]); stdout = io, stderr = devnull); wait = true)
            catch
            end
        end
        occursin(ch, st) || error(
            _juliaup_captured_fail_msg(["add", ch], add, add_out, add_err),
        )
    end
    for args in (["update", ch], ["default", ch])
        proc, out_s, err_s = _juliaup_run_captured(ju, args)
        proc.exitcode == 0 || error(_juliaup_captured_fail_msg(args, proc, out_s, err_s))
    end
    jl = _local_julia_beside_juliaup(ju)
    isfile(jl) || error("Julia not found after juliaup align ($jl)")
    out = read(`$jl --version`, String)
    ver = parse_julia_version(out)
    ver === nothing && error("Julia --version unparseable after juliaup align")
    if julia_version_mismatch_kind(VERSION, ver) == :minor
        error("still mismatched after align: process $(VERSION), juliaup default $ver")
    end
    return (; ver, changed = true)
end

"""Parse remote Julia version via setup SSH transport (`DISTSSHKIT_TEST_SSH`)."""
function _remote_julia_version_setup_ssh(
        host::AbstractString,
        julia_path::AbstractString,
    )::Union{Nothing, VersionNumber}
    pq = _remote_shell_path_word(String(julia_path))
    try
        out = read(
            pipeline(_host_sync_remote_shell_cmd(String(host), "$pq --version"); stderr = devnull),
            String,
        )
        return parse_julia_version(out)
    catch
        return nothing
    end
end

"""
Align each target's juliaup default to `channel` (kit parent major.minor).

Targets may be SSH hosts and/or [`PARENT_HOST_NAME`](@ref) (`parent`). Requires
an existing `juliaup` (official `\$HOME/.juliaup/bin/juliaup` or macOS Homebrew
`/opt/homebrew/bin/juliaup` / `/usr/local/bin/juliaup`). Does not install
juliaup. Runs `add` → `update` → `default`. Confirm unless `confirm=false`.
Changing the default does not alter the Julia process already running this kit.
"""
function juliaup_align_remotes(
        hosts::Vector{String};
        channel::AbstractString = juliaup_channel(),
        confirm::Bool = true,
    )::NamedTuple
    ch = String(channel)
    if confirm && !kit_noninteractive()
        cancelled = with_kit_progress_suspended() do
            print_err("  This will run juliaup add/update/default $ch on each target.\n")
            println_fatal("  That changes the host default Julia.")
            println_fatal("  Targets: $(join(hosts, ", "))")
            println_fatal("  Needs juliaup at \$HOME/.juliaup/bin/juliaup or Homebrew")
            println_fatal("  (/opt/homebrew/bin/juliaup or /usr/local/bin/juliaup).")
            println_fatal("  The running kit process keeps its current Julia until restart.")
            println_fatal()
            kit_confirm("Type 'juliaup' to confirm: "; keyword = "juliaup") || begin
                println_fatal("Cancelled.")
                return true
            end
            println_fatal()
            return false
        end
        cancelled && return (; cancelled = true, succeeded = 0, failed = 0, hosts = HostResult[])
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
            if is_parent_host_name(host)
                r = kit_spin!("  $PARENT_HOST_NAME: ") do
                    _juliaup_align_local!(ch)
                end
                if r.changed
                    print_ok("✓ Julia $(r.ver) (channel $ch)")
                    kit_println()
                    kit_println("    Note: this process still runs Julia $VERSION until you restart.")
                else
                    print_juliaup_already_on!(PARENT_HOST_NAME, ch)
                end
                succeeded += 1
                push!(host_results, HostResult(PARENT_HOST_NAME, true, "juliaup $ch"))
                _setup_host_span!(host, :ok)
                continue
            end
            align_out = kit_spin!("  $host: ") do
                proc = run(
                    pipeline(
                        ignorestatus(_host_sync_remote_shell_cmd(host, remote_sh));
                        stdout = out_buf,
                        stderr = err_buf,
                    );
                    wait = true,
                )
                if proc.exitcode != 0
                    msg = strip(String(take!(err_buf)))
                    isempty(msg) && (msg = strip(String(take!(out_buf))))
                    isempty(msg) && (msg = "juliaup align exit $(proc.exitcode)")
                    error(first(split(msg, '\n')))
                end
                return strip(String(take!(out_buf)))
            end
            if align_out == "already"
                print_juliaup_already_on!(host, ch)
            else
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
                print_juliaup_parent_patch_note!(ver; channel = ch)
            end
            succeeded += 1
            push!(host_results, HostResult(host, true, "juliaup $ch"))
            _setup_host_span!(host, :ok)
        catch e
            detail = strip(String(take!(err_buf)))
            report_remote_failure(e; stderr = detail)
            combined = isempty(detail) ? sprint(showerror, e) : detail
            if occursin("juliaup not found", combined) || occursin("127", combined)
                kit_println("    Install juliaup on $host first (see Requirements), then retry.")
            end
            failed += 1
            push!(host_results, HostResult(host, false, combined))
            _setup_host_span!(host, :fail)
        end
    end
    return (; host_op_result(succeeded = succeeded, failed = failed)..., hosts = host_results)
end

"""Run local `juliaup update` (all installed channels)."""
function _juliaup_update_local!(
        candidates::Vector{String} = local_juliaup_candidates(),
    )
    ju = find_local_juliaup(candidates)
    ju === nothing && error(
        "juliaup not found (tried: $(join(candidates, ", ")))",
    )
    proc, out_s, err_s = _juliaup_run_captured(ju, ["update"])
    proc.exitcode == 0 || error(_juliaup_captured_fail_msg(["update"], proc, out_s, err_s))
    return nothing
end

"""
Run `juliaup update` on each target (installed channels; does not `default`).

Same hosts as `--juliaup` (`child:NAME` and/or `parent`). Confirm unless
`confirm=false`. Does not install juliaup.
"""
function juliaup_update_remotes(
        hosts::Vector{String};
        confirm::Bool = true,
    )::NamedTuple
    if confirm && !kit_noninteractive()
        cancelled = with_kit_progress_suspended() do
            print_err("  This will run juliaup update on each target.\n")
            println_fatal("  Installed channels refresh; the host default is unchanged.")
            println_fatal("  Targets: $(join(hosts, ", "))")
            println_fatal("  Needs juliaup at \$HOME/.juliaup/bin/juliaup or Homebrew")
            println_fatal("  (/opt/homebrew/bin/juliaup or /usr/local/bin/juliaup).")
            println_fatal("  The running kit process keeps its current Julia until restart.")
            println_fatal()
            kit_confirm("Type 'update' to confirm: "; keyword = "update") || begin
                println_fatal("Cancelled.")
                return true
            end
            println_fatal()
            return false
        end
        cancelled && return (; cancelled = true, succeeded = 0, failed = 0, hosts = HostResult[])
    end

    remote_sh = _juliaup_update_remote_sh()
    succeeded = 0
    failed = 0
    host_results = HostResult[]
    for host in hosts
        _setup_host_span!(host, :running)
        err_buf = IOBuffer()
        out_buf = IOBuffer()
        try
            if is_parent_host_name(host)
                kit_spin!("  $PARENT_HOST_NAME: ") do
                    _juliaup_update_local!()
                end
                print_ok("✓ juliaup update")
                kit_println()
                succeeded += 1
                push!(host_results, HostResult(PARENT_HOST_NAME, true, "juliaup update"))
                _setup_host_span!(host, :ok)
                continue
            end
            kit_spin!("  $host: ") do
                proc = run(
                    pipeline(
                        ignorestatus(_host_sync_remote_shell_cmd(host, remote_sh));
                        stdout = out_buf,
                        stderr = err_buf,
                    );
                    wait = true,
                )
                if proc.exitcode != 0
                    msg = strip(String(take!(err_buf)))
                    isempty(msg) && (msg = strip(String(take!(out_buf))))
                    isempty(msg) && (msg = "juliaup update exit $(proc.exitcode)")
                    error(first(split(msg, '\n')))
                end
                return nothing
            end
            print_ok("✓ juliaup update")
            kit_println()
            succeeded += 1
            push!(host_results, HostResult(host, true, "juliaup update"))
            _setup_host_span!(host, :ok)
        catch e
            detail = strip(String(take!(err_buf)))
            report_remote_failure(e; stderr = detail)
            combined = isempty(detail) ? sprint(showerror, e) : detail
            if occursin("juliaup not found", combined) || occursin("127", combined)
                kit_println("    Install juliaup on $host first (see Requirements), then retry.")
            end
            failed += 1
            push!(host_results, HostResult(host, false, combined))
            _setup_host_span!(host, :fail)
        end
    end
    return (; host_op_result(succeeded = succeeded, failed = failed)..., hosts = host_results)
end
