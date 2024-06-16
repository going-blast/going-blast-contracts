// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { AuctioneerHarness } from "./AuctioneerHarness.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerCreateTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_setupAuctioneerTreasury();
		_setupAuctioneerCreator();
	}

	// CREATE
	function test_createAuction_RevertWhen_NotCreatorRole() public {
		_giveWETH(user1, 100e18);
		_approveWeth(user1, address(auctioneer), UINT256_MAX);

		_expectRevertNotCreator(user1);

		AuctionParams memory params = _getBaseAuctionParams();

		vm.prank(user1);
		auctioneer.createAuction(params);

		auctioneer.setCreateAuctionRequiresRole(false);

		vm.expectEmit(true, true, true, true);
		emit AuctionCreated(user1, 0);

		vm.prank(user1);
		auctioneer.createAuction(params);
	}

	function test_createAuction_RevertWhen_TreasuryNotSet() public {
		// SETUP
		_createAndLinkAuctioneers();

		// EXECUTE
		vm.expectRevert(TreasuryNotSet.selector);

		_createAuction(_getBaseAuctionParams());
	}

	function test_createAuction_createSingleAuction_RevertWhen_TokenNotApproved() public {
		// SETUP
		vm.prank(creator);
		WETH.approve(address(auctioneer), 0);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, 1e18));

		// Auction with GO ERC20 reward
		_createAuction(_getBaseAuctionParams());
	}

	function test_createAuction_createSingleAuction_RevertWhen_BalanceInsufficient() public {
		// SETUP
		uint256 creatorWethBal = WETH.balanceOf(creator);
		vm.prank(creator);
		WETH.transfer(address(1), creatorWethBal);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, creator, 0, 1e18));

		_createAuction(_getBaseAuctionParams());
	}

	function test_createAuction_validateUnlock_RevertWhen_UnlockAlreadyPassed() public {
		vm.expectRevert(UnlockAlreadyPassed.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		vm.warp(params.unlockTimestamp + 1);

		_createAuction(params);
	}

	function test_createAuction_validateTokens_RevertWhen_TooManyTokens() public {
		vm.expectRevert(TooManyTokens.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		TokenData[] memory tokens = new TokenData[](5);
		tokens[0] = params.tokens[0];
		tokens[1] = params.tokens[0];
		tokens[2] = params.tokens[0];
		tokens[3] = params.tokens[0];
		tokens[4] = params.tokens[0];

		params.tokens = tokens;

		_createAuction(params);
	}

	function test_createAuction_validateTokens_RevertWhen_NoRewards() public {
		vm.expectRevert(NoRewards.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		TokenData[] memory tokens = new TokenData[](0);
		params.tokens = tokens;

		_createAuction(params);
	}

	function test_createAuction_validateBidWindows_RevertWhen_InvalidBidWindowCount_0() public {
		vm.expectRevert(InvalidBidWindowCount.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		BidWindowParams[] memory windows = new BidWindowParams[](0);
		params.windows = windows;

		_createAuction(params);
	}

	function test_createAuction_validateBidWindows_RevertWhen_InvalidBidWindowCount_5() public {
		vm.expectRevert(InvalidBidWindowCount.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		BidWindowParams[] memory windows = new BidWindowParams[](5);

		windows[0] = params.windows[0];
		windows[1] = params.windows[0];
		windows[2] = params.windows[0];
		windows[3] = params.windows[1];
		windows[4] = params.windows[2];

		params.windows = windows;

		_createAuction(params);
	}

	function test_createAuction_validateBidWindows_RevertWhen_InvalidWindowOrder() public {
		// OPEN AFTER TIMED
		vm.expectRevert(InvalidWindowOrder.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		params.windows[0].windowType = BidWindowType.TIMED;
		params.windows[1].windowType = BidWindowType.OPEN;
		params.windows[2].windowType = BidWindowType.TIMED;

		_createAuction(params);

		// OPEN AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params.windows[0].windowType = BidWindowType.INFINITE;
		params.windows[1].windowType = BidWindowType.OPEN;
		params.windows[2].windowType = BidWindowType.TIMED;

		_createAuction(params);

		// TIMED AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params.windows[0].windowType = BidWindowType.TIMED;
		params.windows[1].windowType = BidWindowType.INFINITE;
		params.windows[2].windowType = BidWindowType.OPEN;

		_createAuction(params);
	}

	function test_createAuction_validateBidWindows_RevertWhen_LastWindowNotInfinite() public {
		vm.expectRevert(LastWindowNotInfinite.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		params.windows[2].windowType = BidWindowType.TIMED;

		_createAuction(params);
	}

	function test_createAuction_validateBidWindows_RevertWhen_MultipleInfiniteWindows() public {
		vm.expectRevert(MultipleInfiniteWindows.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		params.windows[1].windowType = BidWindowType.INFINITE;
		params.windows[2].windowType = BidWindowType.INFINITE;

		_createAuction(params);
	}

	function test_createAuction_validateBidWindows_RevertWhen_OpenWindowTooShort() public {
		vm.expectRevert(WindowTooShort.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		params.windows[1].duration = (1 hours - 1 seconds);

		_createAuction(params);
	}

	function test_createAuction_validateBidWindows_RevertWhen_InvalidBidWindowTimer() public {
		vm.expectRevert(InvalidBidWindowTimer.selector);

		AuctionParams memory params = _getBaseAuctionParams();

		params.windows[2].timer = 29 seconds;

		_createAuction(params);
	}

	// SUCCESSES

	function test_createAuction_createSingleAuction_ExpectEmit_AuctionCreated() public {
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(creator, 0);

		AuctionParams memory params = _getBaseAuctionParams();

		_createAuction(params);
	}

	function test_createAuction_expectLotAndLotCountIncrement() public {
		// Lot 0
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(creator, 0);

		AuctionParams memory params = _getBaseAuctionParams();

		_createAuction(params);
		assertEq(auctioneerAuction.lotCount(), 1, "Lot count is 1");

		// Lot 1
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(creator, 1);

		params = _getBaseAuctionParams();

		_createAuction(params);
		assertEq(auctioneerAuction.lotCount(), 2, "Lot count is 2");

		// Lot 2
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(creator, 2);

		params = _getBaseAuctionParams();

		_createAuction(params);
		assertEq(auctioneerAuction.lotCount(), 3, "Lot count is 3");
	}

	function test_createAuction_createSingleAuction_SuccessfulUpdateOfContractState() public {
		AuctionParams memory params = _getBaseAuctionParams();

		uint256 lotCount = auctioneerAuction.lotCount();

		_prepExpectETHTransfer(0, creator, address(auctioneerAuction));
		_expectTokenTransfer(WETH, creator, address(auctioneer), 1e18);

		_createAuction(params);

		assertEq(auctioneerAuction.lotCount(), lotCount + 1, "Lot count matches");

		_expectETHBalChange(0, address(auctioneerAuction), 1e18);
	}

	function test_createAuction_createSingleAuction_SuccessfulCreationOfAuctionData() public {
		AuctionParams memory params = _getBaseAuctionParams();

		_createAuction(params);

		Auction memory auction = auctioneerAuction.getAuction(0);

		assertEq(auction.lot, 0, "Auction lot should be 0");

		// Check tokens match
		for (uint256 i = 0; i < params.tokens.length; i++) {
			assertEq(auction.rewards.tokens[i].token, params.tokens[i].token, "Tokens match");
			assertEq(auction.rewards.tokens[i].amount, params.tokens[i].amount, "Amounts match");
		}
		for (uint256 i = 0; i < params.nfts.length; i++) {
			assertEq(auction.rewards.nfts[i].nft, params.nfts[i].nft, "Nfts Match");
			assertEq(auction.rewards.nfts[i].id, params.nfts[i].id, "Nft Ids Match");
		}
		assertEq(auction.unlockTimestamp, params.unlockTimestamp, "Unlock timestamp set correctly");
		assertEq(auction.bidData.bids, 0, "Bids should be 0");
		assertEq(auction.bidData.revenue, 0, "Revenue should be 0");
		assertEq(auction.bidData.bid, startingBid, "Initial bid amount should be starting bid");
		assertEq(auction.bidData.bidCost, bidCost, "BidCost should be set correctly");
		assertEq(auction.bidData.bidIncrement, bidIncrement, "BidIncrement should be set correctly");
		assertEq(auction.bidData.bidTimestamp, params.unlockTimestamp, "Last bid timestamp should be unlock timestamp");
		assertEq(auction.bidData.bidUser, address(0), "Bidding user should be empty");
		assertEq(auction.bidData.bidRune, 0, "Bidding rune should be 0");
		assertEq(auction.finalized, false, "Not finalized");

		assertEq(auction.windows.length, params.windows.length, "Param and Auction window number should match");

		// Window types
		for (uint8 i = 0; i < params.windows.length; i++) {
			assertEq(
				uint8(auction.windows[i].windowType),
				uint8(params.windows[i].windowType),
				"Window types should match"
			);
		}

		// Timers
		for (uint8 i = 0; i < params.windows.length; i++) {
			// Timed windows get a 9 second bonus window at the end
			// Open windows should have timer set to 0 (no timer)
			uint256 expectedTimer = params.windows[i].windowType == BidWindowType.OPEN
				? 0
				: params.windows[i].timer + 9;

			assertEq(auction.windows[i].timer, expectedTimer, "Param and Auction window timer should match");
		}

		// Start and stop timestamps
		uint256 startTimestamp = params.unlockTimestamp;
		for (uint8 i = 0; i < params.windows.length; i++) {
			assertEq(auction.windows[i].windowOpenTimestamp, startTimestamp, "Auction window start should be correct");
			uint256 trueWindowDuration = params.windows[i].windowType == BidWindowType.INFINITE
				? 315600000
				: params.windows[i].duration;
			startTimestamp += trueWindowDuration;
			assertEq(auction.windows[i].windowCloseTimestamp, startTimestamp, "Auction window end should be correct");
		}
	}

	// ACTIVE LOTS

	function test_activeLots_lotAddedOnCreate() public {
		AuctionParams memory params = _getBaseAuctionParams();

		assertEq(auctioneer.getActiveLots().length, 0, "No active lots");

		uint256 lot0 = _createAuction(params);

		assertEq(auctioneer.getActiveLots().length, 1, "Auction 1 added to active lots");
		assertEq(auctioneer.getActiveLots()[0], lot0, "Auction lot number added");

		uint256 lot1 = _createAuction(params);

		assertEq(auctioneer.getActiveLots().length, 2, "Auction 2 added to active lots");
		assertEq(auctioneer.getActiveLots()[0], lot0, "Auction 1 lot in list");
		assertEq(auctioneer.getActiveLots()[1], lot1, "Auction 2 lot in list");
	}

	function test_activeLots_lotRemovedOnCancel() public {
		AuctionParams memory params = _getBaseAuctionParams();

		uint256 lot = _createAuction(params);

		assertEq(auctioneer.getActiveLots().length, 1, "Auction added to active lots");
		assertEq(auctioneer.getActiveLots()[0], lot, "Auction lot number added");

		_cancelAuction(lot);

		assertEq(auctioneer.getActiveLots().length, 0, "Auction removed from active lots");
	}

	function test_activeLots_lotRemovedOnFinalize() public {
		AuctionParams memory params = _getBaseAuctionParams();

		uint256 lot = _createAuction(params);

		assertEq(auctioneer.getActiveLots().length, 1, "Auction added to active lots");
		assertEq(auctioneer.getActiveLots()[0], lot, "Auction lot number added");

		_warpToAuctionEndTimestamp(lot);

		auctioneer.finalizeAuction(lot);

		assertEq(auctioneer.getActiveLots().length, 0, "Auction removed from active lots");
	}

	function test_activeLots_lotRemovedOnClaim() public {
		AuctionParams memory params = _getBaseAuctionParams();

		uint256 lot = _createAuction(params);

		assertEq(auctioneer.getActiveLots().length, 1, "Auction added to active lots");
		assertEq(auctioneer.getActiveLots()[0], lot, "Auction lot number added");

		_warpToUnlockTimestamp(lot);

		_bidOnLot(user1, lot);

		_warpToAuctionEndTimestamp(lot);

		uint256 lotPrice = auctioneerAuction.getAuction(lot).bidData.bid;
		vm.deal(user1, lotPrice);
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(lot, "Claimed");

		assertEq(auctioneer.getActiveLots().length, 0, "Auction removed from active lots");
	}
}
