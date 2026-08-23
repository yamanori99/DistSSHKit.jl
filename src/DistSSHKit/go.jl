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

function kit_run_result(result::GoResult)::KitRunResult
    return KitRunResult(
        result.ok,
        :go,
        _optional_path(result.output_dir),
        nothing,
        result.failed_step,
        _result_exit_code(result.ok, result.run, result.collect, result.failed_step),
    )
end

const _GO_IO_LOCK = ReentrantLock()

_go_is_local_host(host_name::AbstractString)::Bool = is_local_host_name(host_name)

"""Sanitize a host name for use as a directory component."""
function _go_sanitize_label(raw::AbstractString)::String
    s = replace(String(raw), r"[^A-Za-z0-9._@+-]+" => "_")
    return isempty(s) ? "host" : s
end

"""True when a go token looks like a misspelling of `parenthost`."""
function _go_local_host_typo_hint(host_name::AbstractString)::Union{Nothing,String}
    h = lowercase(String(host_name))
    h in (
        "lacal", "loacl", "locahost", "locl",
        "parenthos", "parnthost",
        "masterhost", "masterhos", "materhost",
    ) &&
        return "did you mean parenthost?"
    return nothing
end

"""
Build execution slots from host tokens.

- No tokens → one parent slot (directory label `parenthost`)
- `parenthost:N` → N slots on this job's DistSSHKit parent
- `parenthost:0` skips parent when remotes are listed
- `user@host` → one remote slot
- `user@host:N` → N remote slots on that host (`host`, or `host-1` … when N>1)
"""
function _go_plan_slots(host_tokens::AbstractVector{<:AbstractString})::Vector{GoSlot}
    isempty(host_tokens) && return [GoSlot(:local, nothing, PARENT_HOST_NAME)]

    local_count = 0
    parent_label_base = PARENT_HOST_NAME
    remote_runs = Vector{String}() # host repeated per run
    for raw in host_tokens
        host_name, host_workers = split_worker_token(String(raw))
        n = something(host_workers, 1)
        if _go_is_local_host(host_name)
            n < 0 &&
                throw(ArgumentError("parent slot count must be >= 0, got $n in $(repr(raw))"))
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
            "no execution slots: list remotes after parenthost:0, or omit the parent token to run on the parent",
        ))

    slots = GoSlot[]
    if local_count == 1 && isempty(remote_runs)
        push!(slots, GoSlot(:local, nothing, parent_label_base))
    else
        for i in 1:local_count
            label = local_count == 1 ? parent_label_base : "$(parent_label_base)-$i"
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
            host = s.host === nothing ? "parenthost" : s.host
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
    argv = String[julia_bin, "--project=$(project)"]
    job_id = resolved_kit_job_id()
    if job_id !== nothing
        push!(argv, kit_job_eval_arg(job_id))
    end
    push!(argv, String(script))
    append!(argv, collect(String, script_args))
    env_pairs = ["DISTRIBUTED_OUTPUT_DIR" => String(slot_dir)]
    job_id !== nothing && push!(env_pairs, "DISTSSHKIT_JOB_ID" => job_id)
    cmd = addenv(ignorestatus(Cmd(argv)), env_pairs...)
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
    return DriveResult(code == 0, code; output_dir=slot_dir)
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
    # `join(xs, delim)` infers `Union{String,Nothing}` (IO method) on 1.13.
    args_s = sprint() do io
        for a in script_args
            print(io, ' ', _remote_shell_path_word(a))
        end
    end
    jb = _remote_shell_path_word(julia_bin)
    log_q = _remote_shell_path_word(joinpath(slot_rel, "julia.stdout.log"))
    job_id = resolved_kit_job_id()
    job_export = ""
    job_eval = ""
    if job_id !== nothing
        job_export = "export DISTSSHKIT_JOB_ID=$(_remote_shell_path_word(job_id)) && "
        job_eval = " " * _remote_shell_path_word(kit_job_eval_arg(job_id))
    end
    return string(
        "cd $rr && mkdir -p $slot_q && ",
        "export DISTRIBUTED_OUTPUT_DIR=$slot_q && ",
        job_export,
        "$jb$job_eval --project=. $rel_q$args_s >$log_q 2>&1; ",
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
    return DriveResult(code == 0, code; output_dir=slot_dir)
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

function _go_complete!(
    result::GoResult,
    batch_dir::AbstractString,
    release_lock,
    progress_ok::Bool,
    anchor,
)::GoResult
    footer = progress_ok ? display_path(batch_dir, anchor) : nothing
    kit_progress_done!(; ok=progress_ok, footer=footer)
    close_log_file()
    _write_kit_result_file(kit_run_result(result))
    release_lock()
    _remove_kit_pid_file(getpid(), batch_dir, nothing)
    return result
end

"""
    go!(script, workers...; kwargs...)
    go!(script, workers::AbstractVector; kwargs...)

Run an as-is complete job on one or more slots (local and/or remote).

```julia
go!("job.jl")                          # one parent slot
go!("job.jl", "parenthost:2"; args=["8"])
go!("job.jl", "user@h1:1", "user@h2:1"; remote="/path/to/project")
```

Each slot gets `DISTRIBUTED_OUTPUT_DIR` pointing at
`<project>/.distsshkit/go/<stem>_<UTC>/<slot>/`. Setup on remotes is assumed done.
Override the batch root with `output_dir` (CLI: `--output-dir`). For backward
compatibility `collect_spec::AbstractString` also sets the batch root, but passing
both `output_dir` and `collect_spec::String` is an error. `collect_spec === false`
means "skip collect" and is orthogonal to `output_dir`.

Default `sync` is `false` (no pre-run sync; prepare remotes with [`setup!`](@ref)
or CLI `setup` first — `:rsync` / `--rsync` or `:clone` / `--clone`, then
`:instantiate` / `--instantiate`). Pass `sync=:sync` or `sync=:rsync` to sync
before running. Use `sync=:rsync` only onto a missing/empty remote path (or
`setup --delete` / `setup!(session, :delete)` first). `go!` has no git-parity
gate; use [`drive!`](@ref) with `skip_hash_check=false` (CLI: `drive --require-git`)
when you need that.

`julia` sets the Julia binary for each slot (`nothing` / `"auto"` → detect;
same as CLI `--julia`).

`parenthost:N` and `host:N` mean N independent full-job runs (not Distributed workers),
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
    output_dir::Union{Nothing,AbstractString}=nothing,
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
    if output_dir !== nothing && collect_spec isa AbstractString
        throw(ArgumentError(
            "go!: set the batch root via output_dir OR collect_spec::String, not both",
        ))
    end
    batch_dir = if output_dir !== nothing
        canonical_local_path(output_dir)
    elseif collect_spec isa AbstractString
        canonical_local_path(collect_spec)
    else
        _go_batch_output_dir(proj, script_path)
    end
    mkpath(batch_dir)
    release_lock = kit_output_dir_lock!(batch_dir)
    _go_write_batch_manifest!(batch_dir, script_path, slots)
    init_log_file(batch_dir; prefix="go", path_anchor=anchor)

    progress_ok = false
    completed = false
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
        _write_kit_hosts_file(remote_hosts, batch_dir, nothing)
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
                completed = true
                return _go_complete!(
                    GoResult(
                        false,
                        sync_result,
                        nothing,
                        nothing,
                        script_path,
                        batch_dir;
                        failed_step="sync",
                    ),
                    batch_dir,
                    release_lock,
                    false,
                    anchor,
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
            where = s.kind === :local ? "parenthost" : String(something(s.host, s.label))
            writeln_both("  · $(s.label)  ($where)"; color=:light_black)
        end
        writeln_both("")

        n_slots = length(slots)
        if n_slots > 0
            kit_progress_begin!(
                "go";
                steps=n_slots,
                items=String[s.label for s in slots],
                kind=:go,
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
            completed = true
            return _go_complete!(
                GoResult(
                    false,
                    sync_result,
                    last_run[],
                    last_collect[],
                    script_path,
                    batch_dir;
                    failed_step="run",
                ),
                batch_dir,
                release_lock,
                false,
                anchor,
            )
        end
        if any_collect_fail[]
            completed = true
            return _go_complete!(
                GoResult(
                    false,
                    sync_result,
                    last_run[],
                    last_collect[],
                    script_path,
                    batch_dir;
                    failed_step="collect",
                ),
                batch_dir,
                release_lock,
                false,
                anchor,
            )
        end

        writeln_both("")
        writeln_both("Results: $(display_path(batch_dir, anchor))")
        progress_ok = true
        completed = true
        return _go_complete!(
            GoResult(true, sync_result, last_run[], last_collect[], script_path, batch_dir),
            batch_dir,
            release_lock,
            true,
            anchor,
        )
    finally
        if !completed
            footer = progress_ok ? display_path(batch_dir, anchor) : nothing
            kit_progress_done!(; ok=progress_ok, footer=footer)
            close_log_file()
            release_lock()
            _remove_kit_pid_file(getpid(), batch_dir, nothing)
        end
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
    _report_run_header!(io, kit_run_result(result))
    _report_sync_host_errors!(io, result.sync)
    if result.run !== nothing && !result.run.ok
        println(io, "  run exit $(result.run.exit_code)")
    end
    if result.collect !== nothing && !result.collect.ok
        println(io, "  collect exit $(result.collect.exit_code)")
    end
    return false
end

function report_run_errors(result::GoResult; io::IO=stderr)::Bool
    return report_go_errors(result; io=io)
end
