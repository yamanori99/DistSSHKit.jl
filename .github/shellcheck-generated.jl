# Write remote sh bodies from this package's ssh.jl for shellcheck.
# Not part of Pkg.test: macOS and WSL CI images do not have shellcheck.
# The Actions lint workflow runs `shellcheck -s sh -e SC2016 -` on each file.
#
# SC2016 is "this single-quoted string contains $(...)". The fixtures put
# that there so a missing quote fails the parse, and a present quote is the note.
# juliaup, prune, and delete are checked in DistSSHRun.

using DistSSHKit

const R = DistSSHKit
const nasty = "a'b \$(echo pwned)"
const path_tilde = "~/proj/a'b \$(echo pwned)"
const path_abs = "/tmp/a'b \$(echo pwned) ~"

function main(args)
    length(args) == 1 || error("usage: shellcheck-generated.jl DIR")
    dir = args[1]
    mkpath(dir)
    cases = Pair{String, String}[
        "run-on-host" => R._run_on_host_remote_sh([nasty, "a b", "~"]),
        "run-on-host-julia" => R._run_on_host_remote_sh([nasty]; julia = path_abs, detect = false),
        "abs-resolve-tilde" => R._remote_abs_path_resolve_shell(path_tilde),
        "abs-resolve-abs" => R._remote_abs_path_resolve_shell(path_abs),
        "git-hash-tilde" => R._remote_git_hash_inner(path_tilde; short = 7),
        "git-hash-abs" => R._remote_git_hash_inner(path_abs),
    ]
    for (name, script) in cases
        write(joinpath(dir, name * ".sh"), script)
    end
    return nothing
end

main(ARGS)
