#!/bin/sh
# Test double for setup/collect `rsync` (see DISTSSHKIT_TEST_RSYNC).
# A shell script, not Julia: nested `julia` here OOMs 1.11 Pkg.test on GHA.
if [ "${DISTSSHKIT_TEST_RSYNC_FAIL:-}" = "1" ]; then
    exit 1
fi
exit 0
