if !isdefined(Main, :_run_kit_drive)

"""Normalize a host project path for drive subprocesses."""
function _drive_host_root(path)::String
    return abspath(string(path))
end

"""Run the kit `drive` CLI with a host `DISTRIBUTED_PROJECT_ROOT`."""
function _run_kit_drive(;
    script::AbstractString,
    host_root,
    parent_workers::Int=1,
    child_hosts::Vector{String}=String[],
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
    parent_workers > 0 && push!(worker_tokens, "parent:$(parent_workers)")
    append!(worker_tokens, child_hosts)
    isempty(worker_tokens) && error("_run_kit_drive: need parent_workers > 0 or child_hosts")
    cmd = _kit_cli_cmd(
        vcat(["drive"], drive_flags, worker_tokens, log_flags, [script], script_args);
        julia=julia,
        project=kit_root,
    )
    env = _child_julia_env(merge(Dict(
        "DISTRIBUTED_INIT_DELAY_SEC" => "0",
        "DISTRIBUTED_PROJECT_ROOT" => host_root,
    ), extra_env))
    return _run_subprocess(setenv(cmd, env))
end

"""Run `drive --collect-missing|--collect-overwrite ROOT HOST...` as a child CLI."""
function _run_kit_drive_collect(;
    collect_root::AbstractString,
    hosts::Vector{String},
    overwrite::Bool=false,
    host_root,
    kit_root::AbstractString=_kit_root(),
    julia::AbstractString=_julia_exe(),
    extra_env::Dict{String,String}=Dict{String,String}(),
)
    isempty(hosts) && error("_run_kit_drive_collect: need hosts")
    flag = overwrite ? "--collect-overwrite" : "--collect-missing"
    cmd = _kit_cli_cmd(
        vcat(["drive", "-y", "-q", flag, String(collect_root)], hosts);
        julia=String(julia),
        project=String(kit_root),
    )
    env = _child_julia_env(merge(Dict(
        "DISTRIBUTED_PROJECT_ROOT" => _drive_host_root(host_root),
    ), extra_env))
    return _run_subprocess(setenv(cmd, env))
end

"""Run `drive.jl` with `--project` set to a host package."""
function _run_host_drive(;
    script::AbstractString,
    host_project,
    parent_workers::Int=2,
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
               "parent:$(parent_workers)", log_flags..., script])
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
