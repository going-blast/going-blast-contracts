Contracts / tests / deployments

-   Architect

```

Tests to run (remaining)

[x] Auctioneer - NFTs
  [x] NFTs are pulled from wallet into contract
  [x] Pays out all nfts
  [x] NFTs returned if auction cancelled

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

[x] Auctioneer - Winning lot
  [x] Pays out all tokens
  [x] Requires user to pay USD
  [x] Payment can come from funds

[x] Auctioneer - Finalizing auction
  [x] Claiming treasury emissions
  [x] Revenue / profit payouts

[x] Auctioneer - User GO emissions (proof of bid)
  [x] 50% tax on immediate harvest
  [x] 50% tax all the way up to unlock day
  [x] 0% tax after unlocked
  [x] List of farms that can be harvested
  [x] Farm harvest data & unlocks



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
