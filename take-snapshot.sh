SnapshotValue=$(cat snapshot.json | jq -r ".tag")

echo "Printing prev snapshot to verify: $SnapshotValue"

# Capture the output of the `cast rpc evm_snapshot` command
SnapshotValue=$(cast rpc evm_snapshot)

echo $(cat snapshot.json | jq '.tag = '$SnapshotValue) > snapshot.json

# Optional: Print the value to verify
echo "The new snapshot value is: $SnapshotValue"
