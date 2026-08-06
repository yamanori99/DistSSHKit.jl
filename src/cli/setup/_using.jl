# Setup CLI: kit-internal names in `Main` (see `setup.jl`).
using .DistSSHKit:
    check_prerequisites,
    cleanup_remote_workers,
    clone_to_remotes,
    close_log_file,
    delete_remotes,
    finish_host_op!,
    git_sync_project_to_hosts!,
    init_log_file,
    instantiate_remotes,
    kit_println,
    preflight_setup_ssh,
    print_err,
    print_header,
    print_help_blank,
    print_help_chrome,
    print_help_lines,
    print_help_section,
    print_ok,
    println_fatal,
    resolve_clone_url,
    resolve_remote_project_root,
    rsync_push_to_remotes,
    validate_setup_hosts,
    writeln_field

include(joinpath(@__DIR__, "..", "_common.jl"))
