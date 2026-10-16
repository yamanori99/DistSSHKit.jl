# Version text. The regex checks shape. The number comes from Project.toml.

using TOML

@testset "version" begin
    root = pkgdir(DistSSHKit)
    @test root !== nothing
    if root !== nothing
        raw = TOML.parsefile(joinpath(root, "Project.toml"))["version"]
        @test raw isa String
        raw isa String && @test DistSSHKit.dist_ssh_kit_version() == VersionNumber(raw)
    end
    @test DistSSHKit.dist_ssh_kit_version() == pkgversion(DistSSHKit)
    @test :dist_ssh_kit_version in names(DistSSHKit)
    code, out, err = _main_capture(["--version"])
    @test code == 0
    @test isempty(err)
    @test occursin(r"\ADistSSHKit \d+\.\d+\.\d+\nDistSSHRun \S+, DistSSHQueue \S+\n\z", out)
    code, out, err = _main_capture(["go", "--version"])
    @test code == 0
    @test isempty(err)
    @test occursin(r"\ADistSSHKit \d+\.\d+\.\d+\nDistSSHRun \S+, DistSSHQueue \S+\n\z", out)
end
