#!/usr/bin/env julia
# Test double for setup `ssh HOST REMOTE_SCRIPT` (see DISTSSHKIT_TEST_SSH).
#
# Per-host state under DISTSSHKIT_TEST_STATE_ROOT/<slot>/tree represents the
# remote destination directory (missing / empty / nonempty).

function _dest_status(tree::AbstractString)::String
    if !isdir(tree)
        return "MISSING"
    end
    return isempty(readdir(tree)) ? "EMPTY" : "NONEMPTY"
end

function main()
    host = length(ARGS) >= 1 ? ARGS[1] : ""
    script = length(ARGS) >= 2 ? ARGS[2] : ""
    state_root = get(ENV, "DISTSSHKIT_TEST_STATE_ROOT", "")
    if isempty(state_root)
        exit(1)
    end
    slot = replace(host, r"[@:/]" => "_")
    dir = joinpath(state_root, slot)
    tree = joinpath(dir, "tree")

    # Force every probe/op to fail (preflight + delete/clone).
    if get(ENV, "DISTSSHKIT_TEST_SSH_FAIL", "") == "1"
        println(stderr, "Permission denied (publickey).")
        exit(255)
    end

    if occursin("DISTSSHKIT_DEST_STATUS", script)
        println("DISTSSHKIT_DEST_STATUS")
        println(_dest_status(tree))
        exit(0)
    end

    # setup SSH preflight (`echo ok`) and similar probes
    if strip(script) == "echo ok" || strip(script) == "true"
        println("ok")
        exit(0)
    end

    if startswith(strip(script), "test -d")
        if isdir(tree)
            println("ok")
            exit(0)
        end
        exit(1)
    end

    if occursin("test -f", script) && occursin("Project.toml", script)
        if isfile(joinpath(tree, "Project.toml"))
            println("ok")
        end
        exit(0)
    end

    if occursin("mkdir -p", script)
        if get(ENV, "DISTSSHKIT_TEST_MKDIR_FAIL", "") == "1"
            exit(1)
        end
        mkpath(tree)
        exit(0)
    end

    if occursin("git clone", script)
        st = _dest_status(tree)
        if st == "NONEMPTY"
            println("fatal: destination path already exists and is not an empty directory.")
            exit(1)
        end
        mkpath(tree)
        mkpath(joinpath(tree, ".git"))
        println("Cloning into 'tree'...")
        exit(0)
    end

    if occursin("rm -rf", script)
        if isdir(dir)
            rm(dir; recursive=true, force=true)
        end
        exit(0)
    end

    # Job `setup --runtest` (`using Pkg; Pkg.test()`). Preflight is `echo ok`.
    if occursin("Pkg.test()", script)
        if get(ENV, "DISTSSHKIT_TEST_PKG_TEST_FAIL", "") == "1"
            println(stderr, "Test Failed")
            exit(1)
        end
        exit(0)
    end

    if occursin("find ", script) && occursin("-type f", script)
        m = match(r"find\s+(\S+)\s+-type", script)
        find_root = m === nothing ? tree : String(m.captures[1])
        find_root = strip(find_root, ['\'', '"'])
        if isdir(tree)
            for (root, _, files) in walkdir(tree)
                for f in files
                    rel = relpath(joinpath(root, f), tree)
                    println(joinpath(find_root, rel))
                end
            end
        end
        exit(0)
    end

    exit(0)
end

main()
