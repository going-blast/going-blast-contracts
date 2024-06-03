SnapshotValue=$(cat snapshot.json | jq -r ".tag")

# Revert to the previous snapshot
RevertSuccess=$(cast rpc evm_revert $SnapshotValue)

echo "Reverting to snapshot: $SnapshotValue, success: $RevertSuccess"

# Capture the output of the `cast rpc evm_snapshot` command
SnapshotValue=$(cast rpc evm_snapshot)

echo $(cat snapshot.json | jq '.tag = '$SnapshotValue) > snapshot.json

# Optional: Print the value to verify
echo "The new snapshot value is: $SnapshotValue"