if !isdefined(Main, :_write_host_project!)

"""Write a minimal loadable host package (`Project.toml` + `src/Name.jl`)."""
function _write_host_project!(
    proj,
    name::String;
    uuid::Union{Nothing,String}=nothing,
    extra_toml::String="",
)
    proj = abspath(string(proj))
    uuid_line = uuid === nothing ? "" : "uuid = \"$(uuid)\"\n"
    write(
        joinpath(proj, "Project.toml"),
        "name = \"$(name)\"\n$(uuid_line)version = \"0.0.1\"\n$(extra_toml)",
    )
    src = joinpath(proj, "src")
    mkpath(src)
    write(joinpath(src, "$(name).jl"), "module $(name)\nend\n")
    return nothing
end

"""Isolated temp directory removed after `f(path::String)` returns."""
function _with_tempdir(f::Function)
    path::String = abspath(string(mktempdir()))
    try
        return f(path)
    finally
        rm(path; recursive=true, force=true)
    end
end

function _mktemp_host(f::Function)
    return _with_tempdir() do path
        f(abspath(path))
    end
end

function _develop_kit!(host_project::String; kit_root::String=_kit_root(), julia::String=_julia_exe())
    cmd = setenv(
        `$julia --project=$host_project -e "using Pkg; Pkg.develop(path=$(repr(kit_root)))"`,
        _child_julia_env(),
    )
    proc, combined = _run_subprocess(cmd)
    _assert_proc_ok(proc, combined; label="Pkg.develop")
    return nothing
end

end
