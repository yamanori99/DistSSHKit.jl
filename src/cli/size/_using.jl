# size CLI: kit-internal names in `Main` (see `size.jl`).
using .DistSSHKit:
    get_local_resources,
    get_remote_nproc,
    get_remote_total_gb,
    print_header,
    print_help_blank,
    print_help_chrome,
    print_help_lines,
    print_help_section

include(joinpath(@__DIR__, "..", "_common.jl"))
