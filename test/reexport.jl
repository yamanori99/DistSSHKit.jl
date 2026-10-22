# Reexports. Not a guarantee that a future dependency export is wanted.
#
# `_KNOWN_KIT_EXPORTS` is the export set as of DistSSHRun 0.1.9 and
# DistSSHQueue 0.9.6, including `rsync_send_list` (public on Run, reexported
# until 0.11). A dependency patch that adds an `export` fails the test below
# without a Kit change. Read the new name. Update this set in a Kit patch
# when the new export is intended. A public-only name is not reexported, so
# it does not update this set. The 0.11 change that stops reexporting
# public-only names removes `_PUBLIC_ONLY_KEPT` from this set.

const _KNOWN_KIT_EXPORTS = Set(
    (
        :CollectResult,
        :DistSSHKit,
        :DriveHostStatus,
        :DriveResult,
        :GoResult,
        :HostInventory,
        :HostResult,
        :HostRunResult,
        :Job,
        :KitPlan,
        :KitProcess,
        :KitRunResult,
        :KitSession,
        :PipelineConfig,
        :PipelineResult,
        :PlanFinding,
        :Queue,
        :ResourcePool,
        :RideResult,
        :SPINNER_FRAMES,
        :SyncResult,
        :WorkerPlan,
        :allocate_output_dir,
        :allocate_run_dir,
        :cache_file,
        :cache_path,
        :cache_relpath,
        :cache_remote_dir,
        :cancel!,
        :canonical_local_path,
        :collect!,
        :default_store_path,
        :dist_ssh_kit_version,
        :drive!,
        :drive_host_status,
        :execute!,
        :execute_detached_accepts,
        :execute_kwargs_from_parsed,
        :explain_script_not_found,
        :file_sha256,
        :go!,
        :host_tokens,
        :instantiate!,
        :is_parent_host_name,
        :job,
        :job_project,
        :jobs,
        :kit_pid_file_running,
        :kit_result_from_dir,
        :kit_run_dir,
        :kit_run_result,
        :load!,
        :parse_drive_args,
        :parse_go_args,
        :pipeline!,
        :pipeline_config_from_env,
        :plan,
        :pool!,
        :print_cli_error,
        :print_colored,
        :print_help_blank,
        :print_help_chrome,
        :print_help_lines,
        :print_help_section,
        :print_plan,
        :print_pool,
        :print_ride,
        :println_kit_version,
        :push_cache!,
        :read_kit_run_toml,
        :report_go_errors,
        :report_pipeline_errors,
        :report_run_errors,
        :resolve_controller_julia,
        :resolve_pkg_env,
        :resolve_pkg_project_dir,
        :ride!,
        :rsync_send_list,
        :run_on_host,
        :serve,
        :serve!,
        :setup!,
        :short_path,
        :show_drive_usage,
        :show_go_usage,
        :size!,
        :ssh_opts,
        :step!,
        :stored_path,
        :submit!,
        :sync!,
        :terminate!,
        :terminate_run!,
        :worker_pmap,
    )
)

@testset "reexport" begin
    @test DistSSHKit._reexport_name(_PublicOnlyProbe, :shown)
    @test !DistSSHKit._reexport_name(_PublicOnlyProbe, :kept_out)
    @test DistSSHKit._reexport_name(DistSSHRun, :rsync_send_list)
    for n in names(DistSSHRun)
        n === :DistSSHRun && continue
        n === :println_kit_version && continue
        if Base.isexported(DistSSHRun, n) || n in DistSSHKit._PUBLIC_ONLY_KEPT
            @test isdefined(DistSSHKit, n)
            @test n in names(DistSSHKit)
            @test getproperty(DistSSHKit, n) === getproperty(DistSSHRun, n)
        else
            @test !Base.isexported(DistSSHKit, n)
        end
    end
    for n in names(DistSSHQueue)
        n === :DistSSHQueue && continue
        if Base.isexported(DistSSHQueue, n) || n in DistSSHKit._PUBLIC_ONLY_KEPT
            @test isdefined(DistSSHKit, n)
            @test getproperty(DistSSHKit, n) === getproperty(DistSSHQueue, n)
            @test n in names(DistSSHKit)
        else
            @test !Base.isexported(DistSSHKit, n)
        end
    end
    @test !isdefined(DistSSHKit, :_read_kit_pid_record)
    @test !isdefined(DistSSHKit, :_juliaup_default_channel_from_status)
    @test DistSSHKit.go! === DistSSHRun.go!
    @test DistSSHKit.submit! === DistSSHQueue.submit!
end

module _AdoptClashQueued
    function submit!() end
    export submit!
end

module _AdoptClashQualified
    function kit_verbosity() end
    export kit_verbosity
end

@testset "adopt name clash" begin
    before_names = Set(names(DistSSHKit))
    before_from = copy(DistSSHKit._FROM)
    @test haskey(DistSSHKit._FROM, :submit!)
    @test !haskey(DistSSHKit._FROM, :kit_verbosity)
    @test isdefined(DistSSHKit, :kit_verbosity)

    queued = try
        DistSSHKit._adopt!(_AdoptClashQueued)
        nothing
    catch e
        e
    end
    @test queued isa ErrorException
    if queued isa ErrorException
        @test occursin("`submit!`", queued.msg)
        @test occursin(string(nameof(_AdoptClashQueued)), queued.msg)
        @test occursin(string(nameof(DistSSHKit._FROM[:submit!])), queued.msg)
    end

    qualified = try
        DistSSHKit._adopt!(_AdoptClashQualified)
        nothing
    catch e
        e
    end
    @test qualified isa ErrorException
    if qualified isa ErrorException
        @test occursin("`kit_verbosity`", qualified.msg)
        @test occursin(string(nameof(_AdoptClashQualified)), qualified.msg)
        owner = nameof(Base.binding_module(DistSSHKit, :kit_verbosity))
        @test occursin(string(owner), qualified.msg)
    end

    @test Set(names(DistSSHKit)) == before_names
    @test DistSSHKit._FROM == before_from
end

@testset "export surface" begin
    allowed = Set(
        [
            names(DistSSHRun); names(DistSSHQueue);
            :DistSSHKit; :dist_ssh_kit_version; :println_kit_version
        ]
    )
    @test Set(names(DistSSHKit)) ⊆ allowed
    for n in DistSSHKit._OWN
        @test Base.binding_module(DistSSHKit, n) === DistSSHKit
    end
    @test DistSSHKit.println_kit_version !== DistSSHRun.println_kit_version
    @test Set(n for n in names(DistSSHKit) if Base.isexported(DistSSHKit, n)) ==
        _KNOWN_KIT_EXPORTS
    for n in DistSSHKit._QUALIFIED
        @test isdefined(DistSSHKit, n)
    end
end
