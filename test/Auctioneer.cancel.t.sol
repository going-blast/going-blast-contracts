// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerCancelTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
	}

	function test_cancelAuction_RevertWhen_CallerIsNotOwner() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		_expectRevertNotAdmin(address(0));

		vm.prank(address(0));
		auctioneer.cancelAuction(0);
	}

	function test_cancelAuction_RevertWhen_InvalidAuctionLot() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		vm.expectRevert(InvalidAuctionLot.selector);
		auctioneer.cancelAuction(1);
	}

	function test_cancelAuction_RevertWhen_NotCancellable() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		// User bids
		vm.warp(params[0].unlockTimestamp);
		_bid(user1);

		// Revert on cancel
		vm.expectRevert(NotCancellable.selector);
		auctioneer.cancelAuction(0);
	}

	function test_cancelAuction_ExpectEmit_AuctionCancelled() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		// Event
		vm.expectEmit(true, true, true, true);
		emit AuctionCancelled(0);

		auctioneer.cancelAuction(0);
	}

	function test_cancelAuction_Should_ReturnLotToTreasury() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		uint256 treasuryETH = treasury.balance;

		auctioneer.cancelAuction(0);

		assertEq(
			treasury.balance,
			treasuryETH + params[0].tokens[0].amount,
			"Treasury balance should increase by auction amount"
		);
	}

	function test_cancelAuction_Should_MarkAsFinalized() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		auctioneer.cancelAuction(0);

		assertEq(auctioneerAuction.getAuction(0).finalized, true, "Auction should be marked as finalized");
	}

	function test_cancelAuction_Should_ReturnEmissionsToEpoch() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();

		uint256 epoch0EmissionsBeforeAuction = auctioneerEmissions.epochEmissionsRemaining(0);
		auctioneer.createAuctions(params);

		Auction memory auction = auctioneerAuction.getAuction(0);
		uint256 auctionTotalEmission = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;
		uint256 epoch0EmissionsRemaining = auctioneerEmissions.epochEmissionsRemaining(0);

		auctioneer.cancelAuction(0);
		uint256 epoch0EmissionsAfterCancel = auctioneerEmissions.epochEmissionsRemaining(0);

		assertEq(
			auctioneerEmissions.epochEmissionsRemaining(0),
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
		uint256 auctionsOnDayInit = auctioneerAuction.getAuctionsPerDay(day);
		assertEq(auctionsOnDayInit, 0, "Should start with 0 auctions");

		auctioneer.createAuctions(params);

		uint256 auctionsOnDayMid = auctioneerAuction.getAuctionsPerDay(day);
		assertEq(auctionsOnDayMid, 1, "Should add 1 auction to day");

		auctioneer.cancelAuction(0);

		uint256 auctionsOnDayFinal = auctioneerAuction.getAuctionsPerDay(day);
		assertEq(auctionsOnDayFinal, 0, "Should reduce back to 0 after cancel");
	}

	function test_cancelAuction_Should_RemoveBPFromDay() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].emissionBP = 15000;

		uint256 day = params[0].unlockTimestamp / 1 days;
		uint256 bpOnDayInit = auctioneerAuction.dailyCumulativeEmissionBP(day);
		assertEq(bpOnDayInit, 0, "Should start with 0 bp");

		auctioneer.createAuctions(params);

		uint256 bpOnDayMid = auctioneerAuction.dailyCumulativeEmissionBP(day);
		assertEq(bpOnDayMid, 15000, "Should add 15000 bp to day");

		auctioneer.cancelAuction(0);

		uint256 bpOnDayFinal = auctioneerAuction.dailyCumulativeEmissionBP(day);
		assertEq(bpOnDayFinal, 0, "Should reduce bp back to 0 after cancel");
	}

	function test_cancelAuction_RevertWhen_BiddingOnCancelledAuction() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		auctioneer.cancelAuction(0);

		// User bids and should revert
		vm.expectRevert(AuctionNotYetOpen.selector);
		_bid(user1);
	}

	function test_cancelAuction_RevertWhen_AlreadyCancelledNotCancellable() public {
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createAuctions(params);

		auctioneer.cancelAuction(0);

		vm.expectRevert(NotCancellable.selector);
		auctioneer.cancelAuction(0);
	}
}
