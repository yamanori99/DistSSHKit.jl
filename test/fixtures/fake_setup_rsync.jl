#!/usr/bin/env julia
# Test double for setup `rsync` (see DISTSSHKIT_TEST_RSYNC).
if get(ENV, "DISTSSHKIT_TEST_RSYNC_FAIL", "") == "1"
    exit(1)
end
exit(0)
