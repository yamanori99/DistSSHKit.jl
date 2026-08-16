# Loaded first from support.jl (same role as DistSSHKit/drive/runtime/_common.jl).
# Guard: JETLS may analyze this file both via support.jl and as an include leaf.

if !isdefined(Main, :_test_root)

function _test_root()::String
    return abspath(joinpath(@__DIR__, ".."))
end

function _kit_root()::String
    return abspath(joinpath(@__DIR__, "..", ".."))
end

_julia_exe()::String = joinpath(Sys.BINDIR, Base.julia_exename())
_fixture(name::AbstractString) = joinpath(_test_root(), "fixtures", name)

"""`--code-coverage=user` when the parent Julia process is collecting coverage."""
function _julia_coverage_args()::Vector{String}
    Base.JLOptions().code_coverage == 0 && return String[]
    return ["--code-coverage=user"]
end

"""Kit CLI as a child `julia -m DistSSHKit`."""
function _kit_cli_cmd(
    args::AbstractVector{<:AbstractString};
    julia::AbstractString=_julia_exe(),
    project::AbstractString=_kit_root(),
)::Cmd
    prefix = String[
        String(julia),
        "--startup-file=no",
        "--project=$(project)",
        _julia_coverage_args()...,
    ]
    argv = String[String(a) for a in args]
    return Cmd(vcat(prefix, ["-m", "DistSSHKit"], argv))
end

"""Temp hosts file: comment line, `host-a`, and `host-b:4`."""
function _sample_hosts_file()::String
    path, io = mktemp()
    try
        write(io, "# lab hosts (comments and host:N lines)\nhost-a\nhost-b:4\n")
        close(io)
    catch
        close(io)
        rm(path; force=true)
        rethrow()
    end
    return path
end

end
