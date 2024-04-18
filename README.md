Contracts / tests / deployments

-   Architect

```

ToDos:
[x] Change min timer duration to 30s
[x] Allow rune preselection
[x] Add permit option to bidding (self permit + overloaded bid param w/ permit options)

Tests:

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
  [x] Auction not added to claimable lots if no emissions from the auction
  [x] user / rune / auction bids correct

[x] Auctioneer - Voucher
  [x] Vouchers can be used to pay for bids
  [x] Insufficient balance
  [x] Multibid
  [x] Insufficient allowance
  [x] Add revenue field to auction bid data, only increment by bidCost when bidding not using voucher

[x] Auctioneer - USD decimals
  [x] Distributed revenue correct independent of USD decimals
  [x] updateBidCost always expects e18, transforms to eUSDDecimals
  [x] updateStartingBid always expects e18, transforms to eUSDDecimals
  [x] transformDec working

[x] Auctioneer - Runes
  [x] Create
      [x] validate number of runes = 0 | 2-5
      [x] validate no duplicate runeSymbols
      [x] Auction cannot have both runes and nfts
      [x] Rune symbol cannot be 0 (empty rune symbol)
      [x] runes added correctly to auction data from params
          [x] 0 runes added correctly
          [x] multiple runes added correctly
          [x] rune symbols added correctly
          [x] user count and bid count initialized to 0
      [x] Auction.hasRunes is correct
  [x] Bid
      [x] Users bid options rune must be from 0 - runes length - 1, 0 if no runes
      [x] User can't switch rune
      [x] User count of selected rune increased when user places first bid, does not increase on subsequent bids
      [x] Bids are added to rune bid counter
      [x] Users rune is set correctly
      [x] Auction bidding data, bidRune set
  [x] Claim
      [x] User is winner: if auction has rune, winning rune matches user's rune, else winning user matches msg.sender
      [x] User cannot claim winnings multiple times, both with and without runes
      [x] userShareOfLot: 100% (1e18) if winner without runes, user.bids / rune.bids if with runes
      [x] Multiple users can each claim their share of the lot
      [x] Receives userShareOfLot % of lot
      [x] Pays userShareOfLot % of lot price
      [x] Distribute userShareOfLot % of lot price as profit
      [x] Proof of bid works with rune auction



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


[x] Permits
  [x] VOUCHER permit auctioneer
  [x] USD permit auctioneer
  [x] GO permit farm
  [x] GO_LP permit farm
  [x] USD permit auctioneerUser (funds)

[x] Auctioneer - PreselectRune

[x] Auctioneer - Harvest to farm
  [x] Marked as harvested correctly
  [x] Deposits in farm correctly
  [x] Harvests farm
  [x] Locks deposited go
  [x] Transfers go correctly
  [x] Unlock timestamp set to max(current unlock, deposit unlock)
  [x] Withdrawing GO reverts if locked
  [x] Emergency withdrawing GO reverts if locked





```
