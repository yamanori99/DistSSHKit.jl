# go CLI: kit-internal names in `Main` (see `go.jl`).
using .DistSSHKit:
    go!,
    kit_noninteractive,
    print_help_blank,
    print_help_chrome,
    print_help_lines,
    print_help_section,
    println_kit_version,
    report_go_errors

include(joinpath(@__DIR__, "..", "_common.jl"))
