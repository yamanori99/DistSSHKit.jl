# Sequential test-file includes (Test.@testset nesting requires this).

if !isdefined(Main, :_run_test_files!)

"""Include test files under `root` inside nested `@testset`s, one after another."""
function _run_test_files!(root::AbstractString, rels, label::AbstractString)
    for rel in rels
        path = joinpath(root, rel)
        println("▸ ", label, "/", rel)
        @testset "$(label)/$(rel)" verbose=true begin
            include(path)
        end
    end
    return nothing
end

end
