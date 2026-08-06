# Test fixture for `_run_kit_cli_script`: records ARGS after the bridge sets them.
# Defined inside a `let` (rather than as a top-level `function`) so repeated
# `include`s of this fixture within the same process don't trigger Julia's
# "Method definition ... overwritten" warning.
let path = get(ENV, "_DISTSSHKIT_TEST_ARGS_FILE", "")
    if !isempty(path)
        io = open(path, "w")
        try
            for arg in ARGS
                println(io, arg)
            end
        finally
            close(io)
        end
    end
end
