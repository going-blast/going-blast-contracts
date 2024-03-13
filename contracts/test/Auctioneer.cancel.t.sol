// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";

contract AuctioneerCancelTest is AuctioneerHelper {
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

		// Give usd to users
		USD.mint(user1, 1000e18);
		USD.mint(user2, 1000e18);
		USD.mint(user3, 1000e18);
		USD.mint(user4, 1000e18);

		// Users approve auctioneer
		vm.prank(user1);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user2);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user3);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user4);
		USD.approve(address(auctioneer), 1000e18);
	}

	function test_cancelAuction_RevertWhen_CallerIsNotOwner() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));

		vm.prank(address(0));
		auctioneer.cancelAuction(0, true);
	}

	function test_cancelAuction_RevertWhen_InvalidAuctionLot() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		vm.expectRevert(InvalidAuctionLot.selector);
		auctioneer.cancelAuction(1, true);
	}

	function test_cancelAuction_RevertWhen_NotCancellable() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		// User bids
		vm.warp(params[0].unlockTimestamp);
		vm.prank(user1);
		auctioneer.bid(0, 1, false);

		// Revert on cancel
		vm.expectRevert(NotCancellable.selector);
		auctioneer.cancelAuction(0, true);
	}

	function test_cancelAuction_ExpectEmit_AuctionCancelled() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		// Event
		vm.expectEmit(true, true, true, true);
		emit AuctionCancelled(0, sender);

		auctioneer.cancelAuction(0, true);
	}

	function test_cancelAuction_Should_ReturnLotToTreasury() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		uint256 treasuryETH = treasury.balance;

		auctioneer.cancelAuction(0, true);

		assertEq(
			treasury.balance,
			treasuryETH + params[0].tokens[0].amount,
			"Treasury balance should increase by auction amount"
		);
	}

	function test_cancelAuction_Should_MarkAsFinalized() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		auctioneer.cancelAuction(0, true);

		assertEq(auctioneer.getAuction(0).finalized, true, "Auction should be marked as finalized");
	}

	function test_cancelAuction_Should_ReturnEmissionsToEpoch() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		uint256 epoch0EmissionsBeforeAuction = auctioneer.epochEmissionsRemaining(0);
		auctioneer.createDailyAuctions(params);

		Auction memory auction = auctioneer.getAuction(0);
		uint256 auctionTotalEmission = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;
		uint256 epoch0EmissionsRemaining = auctioneer.epochEmissionsRemaining(0);

		auctioneer.cancelAuction(0, true);
		uint256 epoch0EmissionsAfterCancel = auctioneer.epochEmissionsRemaining(0);

		assertEq(
			auctioneer.epochEmissionsRemaining(0),
			epoch0EmissionsRemaining + auctionTotalEmission,
			"Emissions should be freed"
		);

		assertApproxEqAbs(
			epoch0EmissionsBeforeAuction,
			epoch0EmissionsAfterCancel,
			10,
			"Emissions should be the same before and after creating and cancelling auction"
		);
	}

	function test_cancelAuction_Should_RemoveFromAuctionsPerDay() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		uint256 day = params[0].unlockTimestamp / 1 days;
		uint256 auctionsOnDayInit = auctioneer.auctionsPerDay(day);
		assertEq(auctionsOnDayInit, 0, "Should start with 0 auctions");

		auctioneer.createDailyAuctions(params);

		Auction memory auction = auctioneer.getAuction(0);

		uint256 auctionsOnDayMid = auctioneer.auctionsPerDay(day);
		assertEq(auctionsOnDayMid, 1, "Should add 1 auction to day");

		auctioneer.cancelAuction(0, true);

		uint256 auctionsOnDayFinal = auctioneer.auctionsPerDay(day);
		assertEq(auctionsOnDayFinal, 0, "Should reduce back to 0 after cancel");
	}

	function test_cancelAuction_Should_RemoveBPFromDay() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].emissionBP = 15000;

		uint256 day = params[0].unlockTimestamp / 1 days;
		uint256 bpOnDayInit = auctioneer.dailyCumulativeEmissionBP(day);
		assertEq(bpOnDayInit, 0, "Should start with 0 bp");

		auctioneer.createDailyAuctions(params);

		Auction memory auction = auctioneer.getAuction(0);

		uint256 bpOnDayMid = auctioneer.dailyCumulativeEmissionBP(day);
		assertEq(bpOnDayMid, 15000, "Should add 15000 bp to day");

		auctioneer.cancelAuction(0, true);

		uint256 bpOnDayFinal = auctioneer.dailyCumulativeEmissionBP(day);
		assertEq(bpOnDayFinal, 0, "Should reduce bp back to 0 after cancel");
	}

	function test_cancelAuction_RevertWhen_BiddingOnCancelledAuction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		auctioneer.cancelAuction(0, true);

		// User bids and should revert
		vm.expectRevert(BiddingClosed.selector);
		vm.prank(user1);
		auctioneer.bid(0, 1, false);
	}

	function test_cancelAuction_RevertWhen_AlreadyCancelledNotCancellable() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		auctioneer.cancelAuction(0, true);

		vm.expectRevert(NotCancellable.selector);
		auctioneer.cancelAuction(0, true);
	}
}
