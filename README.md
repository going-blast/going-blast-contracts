Contracts / tests / deployments

-   Architect

```

Tests to run (remaining)

[x] Auctioneer - NFTs
  [x] NFTs are pulled from wallet into contract

[x] Auctioneer - Funds
  [x] Adding funds
  [x] Removing funds

[x] Auctioneer - Bids
  [x] Multibid
  [x] Bid can come from funds

[x] Auctioneer - Windows
  [x] Auction does not end during open window
  [x] Ends during timed window if timer expires
  [x] Timed windows can end
  [x] Infinite windows cannot end
  [x] Transition from open window -> open window -> timed window -> timed window -> infinite window (covers all possibilities)

[ ] Auctioneer - Winning lot
  [ ] Pays out all tokens
  [ ] Pays out all nfts
  [ ] Requires user to pay USD
  [ ] Payment can come from funds

[ ] Auctioneer - Finalizing auction
  [ ] Claiming treasury emissions
  [ ] Revenue / profit payouts

[ ] Auctioneer - User GO emissions (proof of bid)
  [ ] 50% tax on immediate harvest
  [ ] 50% tax all the way up to unlock day
  [ ] 0% tax after unlocked
  [ ] List of farms that can be harvested
  [ ] Farm harvest data & unlocks



[ ] AuctioneerFarm - GO Emissions
  [ ] Calculated correctly initially
  [ ] Ends when contract runs out of funds
  [ ] Can be harvested

[ ] AuctioneerFarm - USD Revenue
  [ ] Users earn correct USD
  [ ] USD can be harvested

[ ] AuctioneerFarm - User actions
  [ ] Farm deposit / deposit all
  [ ] Farm withdraw / withdraw all
  [ ] Farm deposit lp / deposit all lp
  [ ] Farm withdraw lp / withdraw all lp
  [ ] Setting lp token



[ ] Auctioneer - Private Lots
  [ ] Calculates GO correctly: (GO + GO staked) * 1 + (LP + LP staked) * 2
  [ ] Private lot bidding unlocking on enough GO owned

```
