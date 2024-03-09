// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";

contract AuctioneerCreateTest is AuctioneerHelper, Test, AuctioneerEvents {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm();
		auctioneer.setTreasury(treasury);

		// Distribute GO
		GO.safeTransfer(address(auctioneer), (GO.totalSupply() * 6000) / 10000);
		GO.safeTransfer(presale, (GO.totalSupply() * 2000) / 10000);
		GO.safeTransfer(treasury, (GO.totalSupply() * 1000) / 10000);
		GO.safeTransfer(liquidity, (GO.totalSupply() * 500) / 10000);
		GO.safeTransfer(address(farm), (GO.totalSupply() * 500) / 10000);

		// Initialize after receiving GO token
		auctioneer.initialize(_getNextDay2PMTimestamp());

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);
	}

	// CREATE
	function test_createDailyAuctions_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		vm.prank(address(0));
		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_RevertWhen_NotInitialized() public {
		// SETUP
		auctioneer = new Auctioneer(USD, GO, WETH, 1e18, 1e16, 1e18, 20e18);

		// EXECUTE
		vm.expectRevert(NotInitialized.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_RevertWhen_TreasuryNotSet() public {
		// SETUP
		auctioneer = new Auctioneer(USD, GO, WETH, 1e18, 1e16, 1e18, 20e18);

		vm.prank(presale);
		GO.safeTransfer(address(auctioneer), 1e18);

		auctioneer.initialize(_getNextDay2PMTimestamp());

		// EXECUTE
		vm.expectRevert(TreasuryNotSet.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_TokenNotApproved() public {
		// SETUP
		vm.prank(treasury);
		WETH.approve(address(auctioneer), 0);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, 1e18));

		AuctionParams[] memory params = new AuctionParams[](1);

		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_BalanceInsufficient() public {
		// SETUP
		uint256 treasuryBalance = WETH.balanceOf(treasury);

		vm.prank(treasury);
		IERC20(address(WETH)).safeTransfer(deployer, treasuryBalance);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, treasury, 0, 1e18));

		AuctionParams[] memory params = new AuctionParams[](1);

		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_TooManyDailyAuctions() public {
		vm.expectRevert(abi.encodeWithSelector(TooManyAuctionsPerDay.selector, 4));

		AuctionParams[] memory params = new AuctionParams[](5);

		AuctionParams memory singleAuctionParam = _getBaseSingleAuctionParams();
		singleAuctionParam.emissionBP = 1000;
		params[0] = singleAuctionParam;
		params[1] = singleAuctionParam;
		params[2] = singleAuctionParam;
		params[3] = singleAuctionParam;
		params[4] = singleAuctionParam;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_RevertWhen_InvalidDailyEmissionBP() public {
		vm.expectRevert(abi.encodeWithSelector(InvalidDailyEmissionBP.selector, 10000, 15000, 1));

		AuctionParams[] memory params = new AuctionParams[](2);

		params[0] = _getBaseSingleAuctionParams();
		params[0].emissionBP = 10000;

		params[1] = _getBaseSingleAuctionParams();
		params[1].emissionBP = 15000;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateUnlock_RevertWhen_UnlockAlreadyPassed() public {
		vm.expectRevert(UnlockAlreadyPassed.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		vm.warp(params[0].unlockTimestamp + 1);

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateTokens_RevertWhen_TooManyTokens() public {
		vm.expectRevert(TooManyTokens.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		address[] memory tokens = new address[](5);
		tokens[0] = params[0].tokens[0];
		tokens[1] = params[0].tokens[0];
		tokens[2] = params[0].tokens[0];
		tokens[3] = params[0].tokens[0];
		tokens[4] = params[0].tokens[0];

		params[0].tokens = tokens;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateTokens_RevertWhen_TokensAndAmountsLengthMismatch() public {
		vm.expectRevert(LengthMismatch.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		address[] memory tokens = new address[](2);
		tokens[0] = params[0].tokens[0];
		tokens[1] = params[0].tokens[0];

		params[0].tokens = tokens;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateTokens_RevertWhen_NoTokens() public {
		vm.expectRevert(NoTokens.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		address[] memory tokens = new address[](0);
		uint256[] memory amounts = new uint256[](0);
		params[0].tokens = tokens;
		params[0].amounts = amounts;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidBidWindowCount_0() public {
		vm.expectRevert(InvalidBidWindowCount.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		BidWindowParams[] memory windows = new BidWindowParams[](0);
		params[0].windows = windows;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidBidWindowCount_5() public {
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

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidWindowOrder() public {
		// OPEN AFTER TIMED
		vm.expectRevert(InvalidWindowOrder.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[0].windowType = BidWindowType.TIMED;
		params[0].windows[1].windowType = BidWindowType.OPEN;
		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createDailyAuctions(params);

		// OPEN AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params[0].windows[0].windowType = BidWindowType.INFINITE;
		params[0].windows[1].windowType = BidWindowType.OPEN;
		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createDailyAuctions(params);

		// TIMED AFTER INFINITE
		vm.expectRevert(InvalidWindowOrder.selector);

		params[0].windows[0].windowType = BidWindowType.TIMED;
		params[0].windows[1].windowType = BidWindowType.INFINITE;
		params[0].windows[2].windowType = BidWindowType.OPEN;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_LastWindowNotInfinite() public {
		vm.expectRevert(LastWindowNotInfinite.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[2].windowType = BidWindowType.TIMED;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_MultipleInfiniteWindows() public {
		vm.expectRevert(MultipleInfiniteWindows.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[1].windowType = BidWindowType.INFINITE;
		params[0].windows[2].windowType = BidWindowType.INFINITE;

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_OpenWindowTooShort() public {
		vm.expectRevert(WindowTooShort.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[1].duration = (1 hours - 1 seconds);

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_validateBidWindows_RevertWhen_InvalidBidWindowTimer() public {
		vm.expectRevert(InvalidBidWindowTimer.selector);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		params[0].windows[2].timer = 59 seconds;

		auctioneer.createDailyAuctions(params);
	}

	// SUCCESSES

	function test_createDailyAuctions_createSingleAuction_ExpectEmit_AuctionCreated() public {
		vm.expectEmit(true, false, false, false);
		emit AuctionCreated(0);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		auctioneer.createDailyAuctions(params);
	}

	function test_createDailyAuctions_createSingleAuction_SuccessfulUpdateOfContractState() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		AuctionParams memory auction = _getBaseSingleAuctionParams();
		params[0] = auction;

		uint256 lotCount = auctioneer.lotCount();

		uint256 day = auction.unlockTimestamp / 1 days;
		uint256 auctionsTodayInit = auctioneer.auctionsPerDay(day);
		uint256 auctionsTodayEmissionsBP = auctioneer.dailyCumulativeEmissionBP(day);

		uint256 treasuryWethBal = WETH.balanceOf(treasury);
		uint256 auctioneerWethBal = WETH.balanceOf(address(auctioneer));

		uint256 expectedEmission = auctioneer.epochEmissionsRemaining(0) / 90;
		uint256 emissionsRemaining = auctioneer.epochEmissionsRemaining(0);

		auctioneer.createDailyAuctions(params);

		assertEq(auctioneer.lotCount(), lotCount + 1);

		assertEq(auctioneer.auctionsPerDay(day), auctionsTodayInit + 1);
		assertEq(auctioneer.dailyCumulativeEmissionBP(day), auctionsTodayEmissionsBP + 10000);

		assertEq(WETH.balanceOf(treasury), treasuryWethBal - 1e18);
		assertEq(WETH.balanceOf(address(auctioneer)), auctioneerWethBal + 1e18);

		assertEq(auctioneer.epochEmissionsRemaining(0), emissionsRemaining - expectedEmission);
	}

	function test_createDailyAuctions_createSingleAuction_SuccessfulCreationOfAuctionData() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		uint256 expectedEmission = auctioneer.epochEmissionsRemaining(0) / 90;

		auctioneer.createDailyAuctions(params);

		Auction memory auction = auctioneer.getAuction(0);

		assertEq(auction.lot, 0);
		assertEq(auction.isPrivate, false);
		assertEq(auction.biddersEmission + auction.treasuryEmission, expectedEmission);
		assertApproxEqAbs(auction.biddersEmission, auction.treasuryEmission * 9, 10);
		assertEq(auction.tokens, params[0].tokens);
		assertEq(auction.amounts, params[0].amounts);
		assertEq(auction.unlockTimestamp, params[0].unlockTimestamp);
		assertEq(auction.bids, 0);
		assertEq(auction.sum, 0);
		assertEq(auction.bid, auctioneer.startingBid());
		assertEq(auction.bidTimestamp, params[0].unlockTimestamp);
		assertEq(auction.bidUser, sender);
		assertEq(auction.claimed, false);
		assertEq(auction.finalized, false);

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
