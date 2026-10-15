using Test

# `/bin/sh` executes the quoted word. A quote that is only syntactically valid
# (for example a double-quoted `$(...)`) still fails here, because the sentinel
# file would exist afterwards.

function _remote_sh_printf(dir::AbstractString, word::AbstractString)::String
    script = "printf %s " * word
    return read(Cmd(`/bin/sh -c $script`; dir = dir), String)
end

@testset "remote shell quote" begin
    @test isfile("/bin/sh")
    mktempdir() do dir::String
        sentinel = joinpath(dir, "SENTINEL")
        touch = "touch " * sentinel
        samples = String[
            "a'b",
            "\$(" * touch * ")",
            "`" * touch * "`",
            "a b",
            ";",
            "|",
            "&",
            "\\",
            "\"",
            "line1\nline2",
            "",
        ]
        for s in samples
            got = _remote_sh_printf(dir, DistSSHKit._remote_sh_quote(s))
            @test got == s
            @test !isfile(sentinel)
        end

        home = _remote_sh_printf(dir, "~")
        rests = String[
            "\$(" * touch * ")",
            "`" * touch * "`",
            "a'b",
            "a b",
            "x;y|&",
        ]
        for rest in rests
            got = _remote_sh_printf(dir, DistSSHKit._remote_shell_path_word("~/" * rest))
            @test got == home * "/" * rest
            @test !isfile(sentinel)
        end

        literals = String[
            "/opt/\$(" * touch * ")",
            "a b;touch " * sentinel,
            "rel/" * "`" * touch * "`",
        ]
        for p in literals
            got = _remote_sh_printf(dir, DistSSHKit._remote_shell_path_word(p))
            @test got == p
            @test !isfile(sentinel)
        end
    end

    err = try
        DistSSHKit._remote_ancestor("~/Repo/proj", "a/proj")
        ""
    catch e
        e isa ArgumentError ? e.msg : sprint(showerror, e)
    end
    @test occursin("--remote-path", err)
    @test occursin("git root", err)
end
