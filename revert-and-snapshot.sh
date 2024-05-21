#!/bin/bash

# Revert to the previous snapshot
revert_success=$(cast rpc evm_revert $SNAPSHOT_VALUE)

echo "Reverting to snapshot: $SNAPSHOT_VALUE, success: $revert_success"

# Capture the output of the `cast rpc evm_snapshot` command
snapshot_value=$(cast rpc evm_snapshot)

# Export the value as an environment variable
export SNAPSHOT_VALUE="$snapshot_value"

# Optional: Print the value to verify
echo "The new snapshot value is: $SNAPSHOT_VALUE"