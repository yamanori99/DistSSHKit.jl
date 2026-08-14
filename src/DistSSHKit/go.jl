# `go` — as-is complete job entry (setup assumed done; sync → exec → collect).

"""One execution slot for [`go!`](@ref) (local or remote)."""
struct GoSlot
    kind::Symbol # :local | :remote
    host::Union{Nothing,String}
    label::String
end

"""Outcome of [`go!`](@ref). On failure, `failed_step` is `"sync"`, `"run"`, or `"collect"`."""
struct GoResult
    ok::Bool
    sync::Union{Nothing,SyncResult}
    run::Union{Nothing,DriveResult}
    collect::Union{Nothing,CollectResult}
    script::String
    output_dir::String
    failed_step::Union{Nothing,String}
end

GoResult(
    ok::Bool,
    sync::Union{Nothing,SyncResult},
    run::Union{Nothing,DriveResult},
    collect::Union{Nothing,CollectResult},
    script::String,
    output_dir::String;
    failed_step::Union{Nothing,String}=nothing,
) = GoResult(ok, sync, run, collect, script, output_dir, failed_step)

const _GO_IO_LOCK = ReentrantLock()

_go_is_local_host(host_name::AbstractString)::Bool = is_local_host_name(host_name)

"""Sanitize a host name for use as a directory component."""
function _go_sanitize_label(raw::AbstractString)::String
    s = replace(String(raw), r"[^A-Za-z0-9._@+-]+" => "_")
    return isempty(s) ? "host" : s
end

"""
Build execution slots from host tokens.

- No tokens → one local slot `local`
- `local:N` / `l:N` → N local slots (`local:0` skips local when remotes are listed)
- `user@host` → one remote slot
- `user@host:N` → N remote slots on that host (`host`, or `host-1` … when N>1)
"""
function _go_local_host_typo_hint(host_name::AbstractString)::Union{Nothing,String}
    h = lowercase(String(host_name))
    h in ("lacal", "loacl", "locahost", "locl") && return "did you mean local?"
    return nothing
end

function _go_plan_slots(host_tokens::AbstractVector{<:AbstractString})::Vector{GoSlot}
    isempty(host_tokens) && return [GoSlot(:local, nothing, "local")]

    local_count = 0
    remote_runs = Vector{String}() # host repeated per run
    for raw in host_tokens
        host_name, host_workers = split_host_workers_spec(String(raw))
        n = something(host_workers, 1)
        if _go_is_local_host(host_name)
            n < 0 &&
                throw(ArgumentError("local slot count must be >= 0, got $n in $(repr(raw))"))
            local_count += n
        elseif n < 1
            hint = _go_local_host_typo_hint(host_name)
            msg = "slot count must be >= 1, got $n in $(repr(raw))"
            hint !== nothing && (msg *= " ($hint)")
            throw(ArgumentError(msg))
        else
            for _ in 1:n
                push!(remote_runs, host_name)
            end
        end
    end

    local_count == 0 && isempty(remote_runs) &&
        throw(ArgumentError(
            "no execution slots: list remotes after local:0, or omit local:0 to run locally",
        ))

    slots = GoSlot[]
    if local_count == 1 && isempty(remote_runs)
        push!(slots, GoSlot(:local, nothing, "local"))
    else
        for i in 1:local_count
            label = local_count == 1 ? "local" : "local-$i"
            push!(slots, GoSlot(:local, nothing, label))
        end
    end

    # Count runs per host for labels
    counts = Dict{String,Int}()
    totals = Dict{String,Int}()
    for h in remote_runs
        totals[h] = get(totals, h, 0) + 1
    end
    for h in remote_runs
        counts[h] = get(counts, h, 0) + 1
        i = counts[h]
        total = totals[h]
        base = _go_sanitize_label(h)
        label = total == 1 ? base : "$base-$i"
        push!(slots, GoSlot(:remote, h, label))
    end
    return slots
end

function _go_script_relpath(project::AbstractString, script::AbstractString)::String
    proj = canonical_local_path(project)
    path = canonical_local_path(script)
    parent_prefix = joinpath(proj, "")
    startswith(path, parent_prefix) || path == proj ||
        throw(ArgumentError("script must be inside project ($proj): $path"))
    rel = relpath(path, proj)
    return rel == "." ? basename(path) : rel
end

"""Batch output directory: `<project>/.distsshkit/go/<stem>_<UTC>/`."""
function _go_batch_output_dir(
    project::AbstractString,
    script::AbstractString;
    now::DateTime=Dates.now(Dates.UTC),
)::String
    proj = canonical_local_path(project)
    stem = splitext(basename(canonical_local_path(script)))[1]
    stamp = Dates.format(now, dateformat"yyyymmddTHHMMSS") * "Z"
    return joinpath(proj, ".distsshkit", "go", "$(stem)_$(stamp)")
end

function _go_host_ssh_hint(host::AbstractString)::String
    h = String(strip(host))
    if !contains(h, '@') && occursin(r"^(?:\d{1,3}\.){3}\d{1,3}$", h)
        return "hint: use user@$h (e.g. root@$h) if SSH defaults to your local username"
    end
    return ""
end

function _go_assert_remote_ready!(host::AbstractString, remote_root::AbstractString)
    rr = _remote_shell_path_word(remote_root)
    inner = "test -d $rr && test -f $rr/Project.toml"
    cmd = Cmd(vcat(["ssh"], collect(ssh_opts()), [String(host), inner]))
    out = IOBuffer()
    err = IOBuffer()
    proc = run(pipeline(ignorestatus(cmd), stdout=out, stderr=err), wait=true)
    if proc.exitcode != 0
        err_text = strip(String(take!(err)))
        ssh_hint = _go_host_ssh_hint(host)
        auth_or_conn = proc.exitcode == 255 ||
            occursin("Permission denied", err_text) ||
            occursin("Connection refused", err_text) ||
            occursin("Could not resolve hostname", err_text) ||
            occursin("No route to host", err_text)

        if auth_or_conn
            msg = "cannot SSH to $host"
            !isempty(err_text) && (msg *= ": $(first(split(err_text, '\n')))")
            !isempty(ssh_hint) && (msg *= "\n  $ssh_hint")
            throw(ArgumentError(msg))
        end

        msg = "remote project not ready on $host ($remote_root).\n" *
            "Run setup first (pick one deploy path), then instantiate:\n" *
            "  rsync:  julia --project=. -m DistSSHKit setup --rsync $host\n" *
            "  git:    julia --project=. -m DistSSHKit setup --clone $host\n" *
            "          (later updates: setup --sync $host)\n" *
            "  then:   julia --project=. -m DistSSHKit setup --instantiate $host\n" *
            "Or from Julia: setup!(session, :rsync, :instantiate)\n" *
            "  (or :clone; repo=\"…\" then :instantiate; later :sync)\n" *
            "Set DISTRIBUTED_REMOTE_PROJECT_ROOT if the remote path is not the default."
        !isempty(ssh_hint) && (msg *= "\n  $ssh_hint")
        throw(ArgumentError(msg))
    end

    deps_err = probe_remote_project_deps(host, remote_root)
    if deps_err !== nothing
        throw(ArgumentError(
            "remote project deps not ready on $host ($remote_root): $deps_err\n" *
            "Fix: julia --project=. -m DistSSHKit setup --instantiate $host\n" *
            "  (or setup!(session, :instantiate) after :rsync / :clone)",
        ))
    end
    return nothing
end

function _go_assert_remotes_ready!(hosts::AbstractVector{<:AbstractString}, remote_root::AbstractString)
    errs = String[]
    for h in hosts
        try
            _go_assert_remote_ready!(h, remote_root)
        catch e
            push!(errs, sprint(showerror, e))
        end
    end
    isempty(errs) && return nothing
    throw(ArgumentError(join(errs, "\n\n")))
end

function _go_julia_exe()::String
    return resolve_controller_julia("auto")
end

"""Resolve Julia binary for `go!` (`nothing` / `"auto"` / empty → detect or local exe).

Remote auto-detect failures throw (no bare `"julia"` PATH fallback).
"""
function _go_resolve_julia(
    ::Nothing=nothing;
    host::Union{Nothing,AbstractString}=nothing,
)::String
    host isa AbstractString || return _go_julia_exe()
    found = resolve_remote_julia(String(host), "auto")
    found === nothing && throw(ArgumentError(
        "Julia not found on remote host $(host) (auto-detect failed)",
    ))
    return found
end

function _go_resolve_julia(
    julia::AbstractString;
    host::Union{Nothing,AbstractString}=nothing,
)::String
    s = strip(String(julia))
    (isempty(s) || lowercase(s) == "auto") && return _go_resolve_julia(nothing; host=host)
    if host isa AbstractString
        found = resolve_remote_julia(String(host), s)
        found === nothing && throw(ArgumentError(
            "Julia not usable on remote host $(host) at $(s)",
        ))
        return found
    end
    return resolve_controller_julia(s)
end

function _go_write_batch_manifest!(
    batch_dir::AbstractString,
    script::AbstractString,
    slots::Vector{GoSlot},
)
    path = joinpath(batch_dir, "go_manifest.txt")
    open(path, "w") do io
        println(io, "script=", script)
        println(io, "slots=", length(slots))
        for (i, s) in enumerate(slots)
            host = s.host === nothing ? "local" : s.host
            println(io, "slot[$i]=", s.label, " kind=", s.kind, " host=", host)
        end
    end
    return path
end

function _go_echo_script_log!(log_path::AbstractString)
    isfile(log_path) || return
    for line in eachline(log_path)
        writeln_both("  " * line)
    end
    return nothing
end

function _go_run_local_slot!(
    project::AbstractString,
    script::AbstractString,
    script_args::AbstractVector{<:AbstractString},
    slot_dir::AbstractString;
    quiet::Bool=false,
    julia::Union{Nothing,AbstractString}=nothing,
)::DriveResult
    mkpath(slot_dir)
    log_path = joinpath(slot_dir, "julia.stdout.log")
    julia_bin = _go_resolve_julia(julia)
    cmd = addenv(
        ignorestatus(
            Cmd(
                vcat(
                    [julia_bin, "--project=$(project)", String(script)],
                    collect(String, script_args),
                ),
            ),
        ),
        "DISTRIBUTED_OUTPUT_DIR" => String(slot_dir),
    )
    proc = open(log_path, "w") do log
        return run(pipeline(cmd; stdout=log, stderr=log); wait=true)
    end
    # Mirror script stdout in `:verbose` only (quiet/progress own the TTY).
    if !quiet && kit_output_detail() && isfile(log_path)
        lock(_GO_IO_LOCK) do
            _go_echo_script_log!(log_path)
            writeln_both("")
        end
    end
    code = proc.exitcode isa Integer ? Int(proc.exitcode) : 1
    return DriveResult(code == 0, code)
end

"""Remote SSH shell snippet for one `go` slot (cd project root before mkdir/log paths)."""
function _go_remote_slot_shell_inner(
    remote_root::AbstractString,
    slot_rel::AbstractString,
    script_rel::AbstractString,
    script_args::AbstractVector{<:AbstractString},
    julia_bin::AbstractString,
)::String
    rr = _remote_shell_path_word(remote_root)
    rel_q = _remote_shell_path_word(script_rel)
    slot_q = _remote_shell_path_word(slot_rel)
    arg_parts = [_remote_shell_path_word(a) for a in script_args]
    args_s = isempty(arg_parts) ? "" : " " * join(arg_parts, " ")
    jb = _remote_shell_path_word(julia_bin)
    log_q = _remote_shell_path_word(joinpath(slot_rel, "julia.stdout.log"))
    return string(
        "cd $rr && mkdir -p $slot_q && ",
        "export DISTRIBUTED_OUTPUT_DIR=$slot_q && ",
        "$jb --project=. $rel_q$args_s >$log_q 2>&1; ",
        "ec=\$?; echo \$ec > $slot_q/go.exitcode; cat $log_q; exit \$ec",
    )
end

function _go_run_remote_slot!(
    host::AbstractString,
    project::AbstractString,
    remote_root::AbstractString,
    script::AbstractString,
    script_args::AbstractVector{<:AbstractString},
    slot_rel::AbstractString,
    slot_dir::AbstractString;
    quiet::Bool=false,
    julia::Union{Nothing,AbstractString}=nothing,
)::DriveResult
    mkpath(slot_dir)
    rel = _go_script_relpath(project, script)
    julia_bin = _go_resolve_julia(julia; host=String(host))
    inner = _go_remote_slot_shell_inner(remote_root, slot_rel, rel, script_args, julia_bin)
    cmd = ignorestatus(Cmd(vcat(["ssh"], collect(ssh_opts()), [String(host), inner])))
    # Capture streams ourselves: piping to the parent's stdout can drop ssh exit codes.
    buf = IOBuffer()
    proc = run(pipeline(cmd; stdout=buf, stderr=buf); wait=true)
    out = String(take!(buf))
    # `:verbose` only: quiet/progress suppress script echo (still in slot logs).
    if !quiet && kit_output_detail() && !isempty(out)
        lock(_GO_IO_LOCK) do
            write(stdout, out)
        end
    end
    code = proc.exitcode isa Integer ? Int(proc.exitcode) : 1
    # Prefer the remote-written exit file when ssh status is unreliable.
    ec_path = joinpath(slot_dir, "go.exitcode")
    try
        remote_ec = string(rstrip(remote_root, '/'), "/", slot_rel, "/go.exitcode")
        run(
            pipeline(
                Cmd(["scp", ssh_opts()..., string(host, ":", remote_ec), ec_path]);
                stdout=devnull,
                stderr=devnull,
            );
            wait=true,
        )
        if isfile(ec_path)
            parsed = tryparse(Int, strip(read(ec_path, String)))
            parsed !== nothing && (code = parsed)
        end
    catch
    end
    return DriveResult(code == 0, code)
end

"""Rsync one remote slot directory into the local slot directory (slot-overwrite collect)."""
function _go_pull_slot!(
    host::AbstractString,
    remote_root::AbstractString,
    slot_rel::AbstractString,
    slot_dir::AbstractString,
)::Bool
    mkpath(slot_dir)
    remote_slot = joinpath(remote_root, slot_rel)
    # Ensure trailing slash semantics: copy contents into slot_dir
    src = remote_slot * "/"
    dest = slot_dir * "/"
    rsync = _host_sync_rsync_argv()
    transport = _host_sync_rsync_transport()
    cmd = ignorestatus(
        Cmd(
            vcat(
                rsync,
                ["-az", "-e", transport, "$(host):$src", dest],
            ),
        ),
    )
    try
        proc = run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=true)
        return proc.exitcode == 0
    catch
        return false
    end
end

"""Run one slot (local process or remote SSH) and optional collect. Isolated env per slot."""
function _go_exec_slot!(
    slot::GoSlot,
    proj::AbstractString,
    script_path::AbstractString,
    args::AbstractVector{<:AbstractString},
    batch_dir::AbstractString,
    sess_rr::AbstractString,
    skip_collect::Bool;
    quiet::Bool=false,
    julia::Union{Nothing,AbstractString}=nothing,
)
    slot_dir = joinpath(batch_dir, slot.label)
    mkpath(slot_dir)
    collect_res = nothing
    collect_fail = false
    if slot.kind === :local
        run_res = _go_run_local_slot!(
            proj, script_path, args, slot_dir; quiet=quiet, julia=julia,
        )
    else
        host = slot.host::String
        slot_rel = relpath(slot_dir, proj)
        run_res = _go_run_remote_slot!(
            host,
            proj,
            sess_rr,
            script_path,
            args,
            slot_rel,
            slot_dir;
            quiet=quiet,
            julia=julia,
        )
        if run_res.ok && !skip_collect
            if _go_pull_slot!(host, sess_rr, slot_rel, slot_dir)
                collect_res = CollectResult(true, 0)
            else
                collect_fail = true
                collect_res = CollectResult(false, 1)
            end
        end
    end
    return (run=run_res, collect=collect_res, collect_fail=collect_fail)
end

"""
    go!(script, workers...; kwargs...)
    go!(script, workers::AbstractVector; kwargs...)

Run an as-is complete job on one or more slots (local and/or remote).

```julia
go!("job.jl")                          # one local slot
go!("job.jl", "local:2"; args=["8"])
go!("job.jl", "user@h1:1", "user@h2:1"; remote="/path/to/project")
```

Each slot gets `DISTRIBUTED_OUTPUT_DIR` pointing at
`<project>/.distsshkit/go/<stem>_<UTC>/<slot>/`. Setup on remotes is assumed done.
Override the batch root with `collect_spec::AbstractString` (CLI: `--output-dir`).

Default `sync` is `false` (no pre-run sync; prepare remotes with [`setup!`](@ref)
or CLI `setup` first — `:rsync` / `--rsync` or `:clone` / `--clone`, then
`:instantiate` / `--instantiate`). Pass `sync=:sync` or `sync=:rsync` to sync
before running. Use `sync=:rsync` only onto a missing/empty remote path (or
`setup --delete` / `setup!(session, :delete)` first). `go!` has no git-parity
gate; use [`drive!`](@ref) with `skip_hash_check=false` (CLI: `drive --require-git`)
when you need that.

`julia` sets the Julia binary for each slot (`nothing` / `"auto"` → detect;
same as CLI `--julia`).

`local:N` and `host:N` mean N independent full-job runs (not Distributed workers),
started together. `path_anchor` shortens displayed paths (CLI passes kit project root).
"""
function go!(
    script::AbstractString,
    workers::AbstractVector{<:AbstractString};
    project::AbstractString=pwd(),
    remote::Union{Nothing,AbstractString}=nothing,
    hosts_file::Union{Nothing,AbstractString}=nothing,
    quiet::Bool=false,
    verbosity::Union{Nothing,Symbol}=nothing,
    yes::Bool=true,
    sync::Union{Symbol,Bool,Nothing}=nothing,
    collect_spec::Union{Bool,AbstractString,Nothing}=nothing,
    args::AbstractVector{<:AbstractString}=String[],
    path_anchor::Union{Nothing,AbstractString}=nothing,
    julia::Union{Nothing,AbstractString}=nothing,
    hint_surface::Symbol=:api,
)::GoResult
    script_path = canonical_local_path(script)
    proj = canonical_local_path(project)
    if !isfile(script_path)
        throw(ArgumentError(explain_script_not_found(
            script_path,
            proj;
            surface=hint_surface,
            headline="script not found: $script_path",
        )))
    end
    anchor = something(path_anchor, proj)

    tokens = String[String(h) for h in workers]
    hf = hosts_file
    if hf === nothing
        env_hf = strip(get(ENV, "DISTSSHKIT_HOSTS_FILE", ""))
        !isempty(env_hf) && (hf = env_hf)
    end
    if hf !== nothing && !isempty(strip(String(hf)))
        for line in read_hosts_file_lines(hf; surface=hint_surface)
            push!(tokens, line)
        end
    end
    slots = _go_plan_slots(tokens)
    batch_dir = if collect_spec isa AbstractString
        canonical_local_path(collect_spec)
    else
        _go_batch_output_dir(proj, script_path)
    end
    mkpath(batch_dir)
    _go_write_batch_manifest!(batch_dir, script_path, slots)
    init_log_file(batch_dir; prefix="go", path_anchor=anchor)

    progress_ok = false
    try
        apply_session_env!(
            KitSession(
                project=proj,
                workers=String[],
                remote=remote,
                quiet=quiet,
                verbosity=verbosity,
                yes=yes,
            ),
        )
        sess_rr = session_remote_root(
            KitSession(
                project=proj,
                workers=String[],
                remote=remote,
                quiet=quiet,
                verbosity=verbosity,
                yes=yes,
            ),
        )

        remote_hosts = unique(String[s.host for s in slots if s.kind === :remote])
        _go_assert_remotes_ready!(remote_hosts, sess_rr)

        sync_result = nothing
        sync_mode = something(sync, false)
        if !isempty(remote_hosts) && sync_mode !== false
            sync_session = KitSession(
                project=proj,
                workers=remote_hosts,
                remote=remote,
                quiet=quiet,
                verbosity=verbosity,
                yes=yes,
            )
            sync_result = sync!(sync_session; mode=sync_mode)
            if !sync_result.ok
                return GoResult(
                    false,
                    sync_result,
                    nothing,
                    nothing,
                    script_path,
                    batch_dir;
                    failed_step="sync",
                )
            end
            # Sync may refresh Manifest without installing; re-check deps before run.
            _go_assert_remotes_ready!(remote_hosts, sess_rr)
        end

        skip_collect = collect_spec === false
        any_run_fail = Ref(false)
        any_collect_fail = Ref(false)
        last_run = Ref(DriveResult(true, 0))
        last_collect = Ref{Union{Nothing,CollectResult}}(nothing)

        print_header("DistSSHKit go")
        writeln_both("")
        writeln_field("Script", display_path(script_path, anchor))
        writeln_field("Slots", string(length(slots)))
        for s in slots
            where = s.kind === :local ? "local" : String(something(s.host, s.label))
            writeln_both("  · $(s.label)  ($where)"; color=:light_black)
        end
        writeln_both("")

        n_slots = length(slots)
        if n_slots > 0
            kit_progress_begin!(
                "go";
                steps=n_slots,
                items=String[s.label for s in slots],
            )
        end
        @sync for slot in slots
            @async begin
                err = nothing
                outcome = try
                    _go_exec_slot!(
                        slot,
                        proj,
                        script_path,
                        args,
                        batch_dir,
                        sess_rr,
                        skip_collect;
                        quiet=quiet,
                        julia=julia,
                    )
                catch e
                    err = e
                    (
                        run=DriveResult(false, 1),
                        collect=nothing,
                        collect_fail=false,
                    )
                end
                lock(_GO_IO_LOCK) do
                    last_run[] = outcome.run
                    if outcome.collect !== nothing
                        last_collect[] = outcome.collect
                    end
                    if outcome.collect_fail
                        any_collect_fail[] = true
                    end
                    if err !== nothing
                        any_run_fail[] = true
                        kit_progress_item!(slot.label; status=:fail)
                        write(stderr, "  ")
                        print_err("✗ $(slot.label): $(sprint(showerror, err))"; io=stderr)
                        println(stderr)
                    elseif !outcome.run.ok
                        any_run_fail[] = true
                        kit_progress_item!(slot.label; status=:fail)
                        write(stderr, "  ")
                        print_err("✗ $(slot.label) (exit $(outcome.run.exit_code))"; io=stderr)
                        println(stderr)
                    else
                        kit_progress_item!(slot.label; status=:ok)
                        ok(slot.label)
                    end
                end
            end
        end

        if any_run_fail[]
            return GoResult(
                false,
                sync_result,
                last_run[],
                last_collect[],
                script_path,
                batch_dir;
                failed_step="run",
            )
        end
        if any_collect_fail[]
            return GoResult(
                false,
                sync_result,
                last_run[],
                last_collect[],
                script_path,
                batch_dir;
                failed_step="collect",
            )
        end

        writeln_both("")
        writeln_both("Results: $(display_path(batch_dir, anchor))")
        progress_ok = true
        return GoResult(true, sync_result, last_run[], last_collect[], script_path, batch_dir)
    finally
        footer = progress_ok ? display_path(batch_dir, anchor) : nothing
        kit_progress_done!(; ok=progress_ok, footer=footer)
        close_log_file()
    end
end

function go!(script::AbstractString; kwargs...)::GoResult
    return go!(script, String[]; kwargs...)
end

function go!(
    script::AbstractString,
    w1::AbstractString,
    rest::AbstractString...;
    kwargs...,
)::GoResult
    return go!(script, String[w1, rest...]; kwargs...)
end

"""
    report_go_errors(result::GoResult; io=stderr)

Print a short summary when [`go!`](@ref) failed. Returns `result.ok`.
"""
function report_go_errors(result::GoResult; io::IO=stderr)::Bool
    result.ok && return true
    step = something(result.failed_step, "unknown")
    println(io, "go failed at step: $step")
    if !isempty(result.output_dir)
        println(io, "  output: $(result.output_dir)")
    end
    if result.sync !== nothing && !result.sync.ok
        for hr in result.sync.hosts
            !hr.ok && println(io, "  sync $(hr.host): $(hr.message)")
        end
    end
    if result.run !== nothing && !result.run.ok
        println(io, "  run exit $(result.run.exit_code)")
    end
    if result.collect !== nothing && !result.collect.ok
        println(io, "  collect exit $(result.collect.exit_code)")
    end
    return false
end
