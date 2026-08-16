# Drive driver that fails on the worker. E2E asserts a real non-zero exit.

function main()
    error("DISTSSHKIT_E2E_REMOTE_FAIL")
end
