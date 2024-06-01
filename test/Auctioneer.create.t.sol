// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { AuctioneerHarness } from "./AuctioneerHarness.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerCreateTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();

		// _giveUsersTokensAndApprove();
		// _auctioneerUpdateFarm();
		// _initializeFarmEmissions();
		// _createDefaultDay1Auction();
	}

	// CREATE
	function test_createAuctions_RevertWhen_CallerIsNotOwner() public {
		_expectRevertNotAdmin(address(0));

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		vm.prank(address(0));
		auctioneer.createAuctions(params);
	}

	function test_createAuctions_RevertWhen_EmissionsNotInitialized() public {
		// SETUP
		_createAndLinkAuctioneers();

		// EXECUTE
		vm.expectRevert(EmissionsNotInitialized.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_RevertWhen_EmissionsNotReceived() public {
		// SETUP
		_createAndLinkAuctioneers();

		vm.expectRevert(EmissionsNotReceived.selector);

		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());
	}

	function test_createAuctions_RevertWhen_TreasuryNotSet() public {
		// SETUP
		_createAndLinkAuctioneers();

		vm.prank(treasury);
		GO.safeTransfer(address(auctioneerEmissions), 1e18);

		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());

		// EXECUTE
		vm.expectRevert(TreasuryNotSet.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_RevertWhen_TeamTreasuryNotSet() public {
		// SETUP
		_createAndLinkAuctioneers();
		_setupAuctioneerTreasury();

		vm.prank(treasury);
		GO.safeTransfer(address(auctioneerEmissions), 1e18);

		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());

		// EXECUTE
		vm.expectRevert(TeamTreasuryNotSet.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_createSingleAuction_RevertWhen_TokenNotApproved() public {
		// SETUP
		vm.prank(treasury);
		WETH.approve(address(auctioneer), 0);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, 1e18));

		AuctionParams[] memory params = new AuctionParams[](1);

		// Auction with GO ERC20 reward
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_createSingleAuction_RevertWhen_BalanceInsufficient() public {
		// SETUP
		uint256 treasuryWethBal = WETH.balanceOf(treasury);
		vm.prank(treasury);
		WETH.transfer(address(1), treasuryWethBal);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, treasury, 0, 1e18));

		AuctionParams[] memory params = new AuctionParams[](1);

		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_createSingleAuction_RevertWhen_TooManyDailyAuctions() public {
		vm.expectRevert(TooManyAuctionsPerDay.selector);

		AuctionParams[] memory params = new AuctionParams[](5);

		AuctionParams memory singleAuctionParam = _getBaseSingleAuctionParams();
		singleAuctionParam.emissionBP = 1000;
		params[0] = singleAuctionParam;
		params[1] = singleAuctionParam;
		params[2] = singleAuctionParam;
		params[3] = singleAuctionParam;
		params[4] = singleAuctionParam;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_createSingleAuction_RevertWhen_InvalidDailyEmissionBP() public {
		vm.expectRevert(InvalidDailyEmissionBP.selector);

		AuctionParams[] memory params = new AuctionParams[](2);

		params[0] = _getBaseSingleAuctionParams();
		params[0].emissionBP = 17500;

		params[1] = _getBaseSingleAuctionParams();
		params[1].emissionBP = 25000;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateUnlock_RevertWhen_UnlockAlreadyPassed() public {
		vm.expectRevert(UnlockAlreadyPassed.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		vm.warp(params[0].unlockTimestamp + 1);

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateTokens_RevertWhen_TooManyTokens() public {
		vm.expectRevert(TooManyTokens.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		TokenData[] memory tokens = new TokenData[](5);
		tokens[0] = params[0].tokens[0];
		tokens[1] = params[0].tokens[0];
		tokens[2] = params[0].tokens[0];
		tokens[3] = params[0].tokens[0];
		tokens[4] = params[0].tokens[0];

		params[0].tokens = tokens;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateTokens_RevertWhen_NoRewards() public {
		vm.expectRevert(NoRewards.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		TokenData[] memory tokens = new TokenData[](0);
		params[0].tokens = tokens;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateBidWindows_RevertWhen_InvalidBidWindowCount_0() public {
		vm.expectRevert(InvalidBidWindowCount.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		BidWindowParams[] memory windows = new BidWindowParams[](0);
		params[0].windows = windows;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateBidWindows_RevertWhen_InvalidBidWindowCount_5() public {
		vm.expectRevert(InvalidBidWindowCount.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		BidWindowParams[] memory windows = new BidWindowParams[](5);

		windows[0] = params[0].windows[0];
		windows[1] = params[0].windows[0];
		windows[2] = params[0].windows[0];
		windows[3] = params[0].windows[1];
		windows[4] = params[0].windows[2];

		params[0].windows = windows;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateBidWindows_RevertWhen_InvalidWindowOrder() public {
		// OPEN AFTER TIMED
		vm.expectRevert(InvalidWindowOrder.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[0].windowType = BidWindowType.TIMED;
		params[0].windows[1].windowType = BidWindowType.OPEN;
		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createAuctions(params);

		// OPEN AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params[0].windows[0].windowType = BidWindowType.INFINITE;
		params[0].windows[1].windowType = BidWindowType.OPEN;
		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createAuctions(params);

		// TIMED AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params[0].windows[0].windowType = BidWindowType.TIMED;
		params[0].windows[1].windowType = BidWindowType.INFINITE;
		params[0].windows[2].windowType = BidWindowType.OPEN;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateBidWindows_RevertWhen_LastWindowNotInfinite() public {
		vm.expectRevert(LastWindowNotInfinite.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateBidWindows_RevertWhen_MultipleInfiniteWindows() public {
		vm.expectRevert(MultipleInfiniteWindows.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[1].windowType = BidWindowType.INFINITE;
		params[0].windows[2].windowType = BidWindowType.INFINITE;

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateBidWindows_RevertWhen_OpenWindowTooShort() public {
		vm.expectRevert(WindowTooShort.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[1].duration = (1 hours - 1 seconds);

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_validateBidWindows_RevertWhen_InvalidBidWindowTimer() public {
		vm.expectRevert(InvalidBidWindowTimer.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[2].timer = 29 seconds;

		auctioneer.createAuctions(params);
	}

	// SUCCESSES

	function test_createAuctions_createSingleAuction_ExpectEmit_AuctionCreated() public {
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(0);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
	}

	function test_createAuctions_expectLotAndLotCountIncrement() public {
		// Lot 0
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(0);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
		assertEq(auctioneerAuction.lotCount(), 1, "Lot count is 1");

		// Lot 1
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(1);

		params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
		assertEq(auctioneerAuction.lotCount(), 2, "Lot count is 2");

		// Lot 2
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(2);

		params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createAuctions(params);
		assertEq(auctioneerAuction.lotCount(), 3, "Lot count is 3");
	}

	function test_createAuctions_createSingleAuction_SuccessfulUpdateOfContractState() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		AuctionParams memory auction = _getBaseSingleAuctionParams();
		params[0] = auction;

		uint256 lotCount = auctioneerAuction.lotCount();

		uint256 day = auction.unlockTimestamp / 1 days;
		uint256 auctionsTodayInit = auctioneerAuction.getAuctionsPerDay(day);
		uint256 auctionsTodayEmissionsBP = auctioneerAuction.dailyCumulativeEmissionBP(day);

		uint256 expectedEmission = auctioneerEmissions.epochEmissionsRemaining(0) / 90;
		uint256 emissionsRemaining = auctioneerEmissions.epochEmissionsRemaining(0);

		_prepExpectETHTransfer(0, treasury, address(auctioneerAuction));
		_expectTokenTransfer(WETH, treasury, address(auctioneer), 1e18);

		auctioneer.createAuctions(params);

		assertEq(auctioneerAuction.lotCount(), lotCount + 1, "Lot count matches");

		assertEq(auctioneerAuction.getAuctionsPerDay(day), auctionsTodayInit + 1, "Auctions per day matches");
		assertEq(
			auctioneerAuction.dailyCumulativeEmissionBP(day),
			auctionsTodayEmissionsBP + 10000,
			"Daily cumulative emission bp matches"
		);

		assertEq(auctioneerEmissions.epochEmissionsRemaining(0), emissionsRemaining - expectedEmission);

		_expectETHBalChange(0, address(auctioneerAuction), 1e18);
	}

	function test_createAuctions_createSingleAuction_SuccessfulCreationOfAuctionData() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		EpochData memory epoch = auctioneerEmissions.getEpochDataAtTimestamp(block.timestamp);
		console.log("Days remaining", epoch.daysRemaining);

		uint256 expectedEmission = auctioneerEmissions.epochEmissionsRemaining(0) / 90;

		auctioneer.createAuctions(params);

		Auction memory auction = auctioneerAuction.getAuction(0);

		assertEq(auction.lot, 0, "Auction lot should be 0");
		assertEq(auction.isPrivate, false, "Auction should not be private");
		assertApproxEqAbs(
			auction.emissions.biddersEmission + auction.emissions.treasuryEmission,
			expectedEmission,
			10,
			"Auction emission split matches"
		);
		assertApproxEqAbs(
			auction.emissions.biddersEmission,
			auction.emissions.treasuryEmission * 9,
			10,
			"Bidders emission is 90%, treasury 10%"
		);
		assertEq(auction.rewards.estimatedValue, params[0].lotValue, "Lot value matches");
		// Check tokens match
		for (uint256 i = 0; i < params[0].tokens.length; i++) {
			assertEq(auction.rewards.tokens[i].token, params[0].tokens[i].token, "Tokens match");
			assertEq(auction.rewards.tokens[i].amount, params[0].tokens[i].amount, "Amounts match");
		}
		for (uint256 i = 0; i < params[0].nfts.length; i++) {
			assertEq(auction.rewards.nfts[i].nft, params[0].nfts[i].nft, "Nfts Match");
			assertEq(auction.rewards.nfts[i].id, params[0].nfts[i].id, "Nft Ids Match");
		}
		assertEq(auction.unlockTimestamp, params[0].unlockTimestamp, "Unlock timestamp set correctly");
		assertEq(auction.bidData.bids, 0, "Bids should be 0");
		assertEq(auction.bidData.revenue, 0, "Revenue should be 0");
		assertEq(auction.bidData.bid, auctioneerAuction.startingBid(), "Initial bid amount should be starting bid");
		assertEq(
			auction.bidData.bidTimestamp,
			params[0].unlockTimestamp,
			"Last bid timestamp should be unlock timestamp"
		);
		assertEq(auction.bidData.bidUser, address(0), "Bidding user should be empty");
		assertEq(auction.bidData.bidRune, 0, "Bidding rune should be 0");
		assertEq(auction.finalized, false, "Not finalized");

		assertEq(auction.windows.length, params[0].windows.length, "Param and Auction window number should match");

		// Window types
		for (uint8 i = 0; i < params[0].windows.length; i++) {
			assertEq(
				uint8(auction.windows[i].windowType),
				uint8(params[0].windows[i].windowType),
				"Window types should match"
			);
		}

		// Timers
		for (uint8 i = 0; i < params[0].windows.length; i++) {
			// Timed windows get a 9 second bonus window at the end
			// Open windows should have timer set to 0 (no timer)
			uint256 expectedTimer = params[0].windows[i].windowType == BidWindowType.OPEN
				? 0
				: params[0].windows[i].timer + 9;

			assertEq(auction.windows[i].timer, expectedTimer, "Param and Auction window timer should match");
		}

		// Start and stop timestamps
		uint256 startTimestamp = params[0].unlockTimestamp;
		for (uint8 i = 0; i < params[0].windows.length; i++) {
			assertEq(auction.windows[i].windowOpenTimestamp, startTimestamp, "Auction window start should be correct");
			uint256 trueWindowDuration = params[0].windows[i].windowType == BidWindowType.INFINITE
				? 315600000
				: params[0].windows[i].duration;
			startTimestamp += trueWindowDuration;
			assertEq(auction.windows[i].windowCloseTimestamp, startTimestamp, "Auction window end should be correct");
		}
	}
}
