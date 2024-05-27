# Get Auctioneer contract address
AuctioneerAddress=$(cat data/anvil/deployment.json | jq -r ".contracts.Auctioneer")

# Get AuctioneerAuction contract address
AuctioneerAuctionAddress=$(cat data/anvil/deployment.json | jq -r ".contracts.AuctioneerAuction")

# Get AuctioneerUser contract address
AuctioneerUserAddress=$(cat data/anvil/deployment.json | jq -r ".contracts.AuctioneerUser")

# Get Deployment first block
FirstBlock=$(cat data/anvil/deployment.json | jq -r ".firstBlock")
# FirstBlock=50

echo "Auctioneer: $AuctioneerAddress"
echo "AuctioneerAuction: $AuctioneerAuctionAddress"
echo "AuctioneerUser: $AuctioneerUserAddress"
echo "FirstBlock: $FirstBlock"

# https://unix.stackexchange.com/questions/164508/why-do-newline-characters-get-lost-when-using-command-substitution
IFS=

# Update Auctioneer Address and StartBlock
echo $(cat subgraph.yaml | yq -y '.dataSources[0].source.address = "'$AuctioneerAddress'" | .dataSources[0].source.startBlock = '$FirstBlock) > subgraph.yaml

# Update Auctioneer Auction Address and StartBlock
echo $(cat subgraph.yaml | yq -y '.dataSources[1].source.address = "'$AuctioneerAuctionAddress'" | .dataSources[1].source.startBlock = '$FirstBlock) > subgraph.yaml

# Update Auctioneer User Address and StartBlock
echo $(cat subgraph.yaml | yq -y '.dataSources[2].source.address = "'$AuctioneerUserAddress'" | .dataSources[1].source.startBlock = '$FirstBlock) > subgraph.yaml

# Create local subgraph
yarn graph-create-local