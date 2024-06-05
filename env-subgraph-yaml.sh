# Get Auctioneer contract address
AuctioneerAddress=$(cat data/anvil/deployment.json | jq -r ".contracts.Auctioneer")

# Get Deployment first block
FirstBlock=$(cat data/anvil/deployment.json | jq -r ".firstBlock")
# FirstBlock=50

echo "Auctioneer: $AuctioneerAddress"
echo "FirstBlock: $FirstBlock"

# https://unix.stackexchange.com/questions/164508/why-do-newline-characters-get-lost-when-using-command-substitution
IFS=

# Update Auctioneer Address and StartBlock
echo $(cat subgraph.yaml | yq -y '.dataSources[0].source.address = "'$AuctioneerAddress'" | .dataSources[0].source.startBlock = '$FirstBlock) > subgraph.yaml
