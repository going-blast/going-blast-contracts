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
  [x] USD sent to farm, increases farm usdRewardPerShare

[x] Auctioneer - User GO emissions (proof of bid)
  [x] 50% tax on immediate harvest
  [x] 50% tax all the way up to unlock day
  [x] 0% tax after unlocked
  [x] List of farms that can be harvested
  [x] Farm harvest data & unlocks



[x] AuctioneerFarm - GO Emissions
  [x] Calculated correctly initially
  [x] Ends when contract runs out of funds
  [x] Can be harvested

[x] AuctioneerFarm - USD Revenue
  [x] Receive from auctioneer
  [x] If 0 staked, return false, fallback to send to treasury
  [x] Users earn correct USD
  [x] USD can be harvested


[x] AuctioneerFarm - LP
	[x] admin
    [x] onlyOwner addLp/removeLp/updateLpBoost
    [x] validBoostRange addLp/updateLpBoost
    [x] emits events addLp/removeLp/updateLpBoost
	  [x] updates state addLp/removeLp/updateLpBoost
	[x] base
	  [x] equalizedUserStaked correct
	  [x] equalizedTotalStaked correct
	[x] addLp
	  [x] should not change users pending
	  [x] added lp depositable
	  [x] equalized staked amounts correct
	[x] removeLp
	  [x] should not change users pending
	  [x] removed lp withdrawable
	  [x] equalized staked amounts correct
	[x] updateLpBoost
	  [x] should not change users pending
	  [x] equalized staked amounts correct



[x] AuctioneerFarm - User actions
  [x] Farm deposit
  [x] Farm withdraw
  [x] Farm harvest
    [x] Updates users debts
    [x] Emits events
    [x] Not transfer if pending is 0
    [x] Harvested matches pending
    [x] goPerShare brought current

[x] AuctioneerFarmV2
  [x] Emergency withdrawal
  [x] Voucher emissions
  [x] Harvest all
  [x] to
    [x] deposit
    [x] withdraw
    [x] harvest
    [x] allHarvest
    [x] emergencyWithdraw



[x] Auctioneer / Farm interaction
  [x] Private lot bidding unlocking on enough GO owned
  [x] Lot profit sent to farm increases usdRewardPerShare

```
