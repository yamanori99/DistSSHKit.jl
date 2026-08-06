if !isdefined(Main, :_run_kit_drive)

"""Normalize a host project path for drive subprocesses."""
function _drive_host_root(path::Union{AbstractString, Base.Filesystem.DirEntry})::String
    if path isa Base.Filesystem.DirEntry
        return abspath(joinpath(path.dir, path.name))
    end
    return abspath(String(path))
end

"""Run `julia -m DistSSHKit drive` with a host `DISTRIBUTED_PROJECT_ROOT`."""
function _run_kit_drive(;
    script::AbstractString,
    host_root::Union{AbstractString, Base.Filesystem.DirEntry},
    local_workers::Int=1,
    remote_hosts::Vector{String}=String[],
    log_dir::Union{Nothing,String}=nothing,
    script_args::Vector{String}=String[],
    kit_root::AbstractString=_kit_root(),
    julia::AbstractString=_julia_exe(),
    drive_flags::Vector{String}=String[],
    extra_env::Dict{String,String}=Dict{String,String}(),
)
    script = String(script)
    host_root = _drive_host_root(host_root)
    kit_root = String(kit_root)
    julia = String(julia)
    log_flags = log_dir === nothing ? ["--no-log"] : ["--log-dir", log_dir]
    worker_tokens = String[]
    local_workers > 0 && push!(worker_tokens, "local:$(local_workers)")
    append!(worker_tokens, remote_hosts)
    isempty(worker_tokens) && error("_run_kit_drive: need local_workers > 0 or remote_hosts")
    cmd = Cmd(vcat(
        [julia, "--startup-file=no", "--project=$kit_root", "-m", "DistSSHKit", "drive"],
        drive_flags,
        worker_tokens,
        log_flags,
        [script],
        script_args,
    ))
    env = _child_julia_env(merge(Dict(
        "DISTRIBUTED_INIT_DELAY_SEC" => "0",
        "DISTRIBUTED_PROJECT_ROOT" => host_root,
    ), extra_env))
    return _run_subprocess(setenv(cmd, env))
end

"""Run `drive.jl` with `--project` set to a host package."""
function _run_host_drive(;
    script::AbstractString,
    host_project::Union{AbstractString, Base.Filesystem.DirEntry},
    local_workers::Int=2,
    log_dir::Union{Nothing,String}=nothing,
    kit_root::AbstractString=_kit_root(),
    julia::AbstractString=_julia_exe(),
)
    script = String(script)
    host_project = _drive_host_root(host_project)
    kit_root = String(kit_root)
    julia = String(julia)
    drive = joinpath(kit_root, "src", "cli", "drive.jl")
    log_flags = log_dir === nothing ? ["--no-log"] : ["--log-dir", log_dir]
    cmd = Cmd([julia, "--startup-file=no", "--project=$host_project", drive,
               "local:$(local_workers)", log_flags..., script])
    env = _child_julia_env(Dict(
        "DISTRIBUTED_INIT_DELAY_SEC" => "0",
        "DISTRIBUTED_PROJECT_ROOT" => host_project,
    ))
    return _run_subprocess(setenv(cmd, env))
end

"""Run a local drive subprocess with logging enabled; assert console + log contents."""
function _assert_drive_log_output(; cmd::Cmd, log_dir::String)
    proc, combined = _run_subprocess(cmd)

    _assert_proc_ok(proc, combined; label="drive log smoke")
    @test occursin("DISTSSHKIT_RUNNER_SMOKE_OK nw=2", combined)
    @test occursin("Results:", combined)

    log_files = String[
        name for name in readdir(log_dir)
        if startswith(name, "drive_") && endswith(name, ".log")
    ]
    @test length(log_files) == 1
    log_content = read(joinpath(log_dir, only(log_files)), String)

    for needle in (
        "Subcommand args: drive",
        "Julia binary:",
        "Script:",
        "Workers:",
        "Running script...",
        "DISTSSHKIT_RUNNER_SMOKE_OK nw=2",
        "Results:",
    )
        @test occursin(needle, log_content)
    end

    return combined, log_content
end

end
