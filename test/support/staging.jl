if !isdefined(Main, :_stage_with_kit_demos)

"""Copy bundled `demos/with_kit/*.jl` into a temp host project for drive tests."""
function _stage_with_kit_demos!(demos_dir::String, kit_root::String)
    host_root = dirname(demos_dir)
    _write_host_project!(
        host_root,
        "DemoHost";
        uuid="22222222-2222-4222-8222-222222222222",
    )
    _develop_kit!(host_root; kit_root=kit_root)
    with_kit_dest = joinpath(demos_dir, "with_kit")
    mkpath(with_kit_dest)
    for name in ("square_file.jl", "square_echo.jl")
        src = joinpath(kit_root, "demos", "with_kit", name)
        isfile(src) || error("missing demo: $src")
        cp(src, joinpath(with_kit_dest, name); force=true)
    end
end

end
