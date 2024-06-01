// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { AuctioneerHarness } from "./AuctioneerHarness.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerEmissionsTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();
	}

	// INITIALIZE

	function test_initialize_RevertWhen_EmissionsNotReceived() public {
		_createAndLinkAuctioneers();

		vm.expectRevert(EmissionsNotReceived.selector);

		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());
	}
	function test_initialize_RevertWhen_AlreadyInitialized() public {
		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());

		vm.expectRevert(AlreadyInitialized.selector);

		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());
	}

	function test_initialize_ExpectEmit_InitializedEmissions() public {
		vm.expectEmit(false, false, false, false);
		emit InitializedEmissions();

		auctioneerEmissions.initializeEmissions(_getNextDay2PMTimestamp());
	}

	function test_initialize_EmissionsSetCorrectly() public {
		uint256 emissionsGenesisDay = (block.timestamp / 1 days) + 3;
		auctioneerEmissions.initializeEmissions(emissionsGenesisDay * 1 days);

		assertEq(auctioneerEmissions.emissionsGenesisDay(), emissionsGenesisDay);

		assertGt(auctioneerEmissions.epochEmissionsRemaining(0), 0);
		assertApproxEqAbs(
			auctioneerEmissions.epochEmissionsRemaining(0),
			auctioneerEmissions.epochEmissionsRemaining(1) * 2,
			10
		);
		assertApproxEqAbs(
			auctioneerEmissions.epochEmissionsRemaining(1),
			auctioneerEmissions.epochEmissionsRemaining(2) * 2,
			10
		);
		assertApproxEqAbs(
			auctioneerEmissions.epochEmissionsRemaining(2),
			auctioneerEmissions.epochEmissionsRemaining(3) * 2,
			10
		);
		assertApproxEqAbs(
			auctioneerEmissions.epochEmissionsRemaining(3),
			auctioneerEmissions.epochEmissionsRemaining(4) * 2,
			10
		);
		assertApproxEqAbs(
			auctioneerEmissions.epochEmissionsRemaining(4),
			auctioneerEmissions.epochEmissionsRemaining(5) * 2,
			10
		);
		assertApproxEqAbs(
			auctioneerEmissions.epochEmissionsRemaining(5),
			auctioneerEmissions.epochEmissionsRemaining(6) * 2,
			10
		);
		assertApproxEqAbs(
			auctioneerEmissions.epochEmissionsRemaining(6),
			auctioneerEmissions.epochEmissionsRemaining(7) * 2,
			10
		);
	}

	// EPOCHS

	// function testFuzz_emissions_AllEmissionsGetUsed(uint256 bp) public {
	// 	vm.assume(bp >= 10000 && bp <= 40000);

	// 	uint256 timestamp = ((block.timestamp / 1 days) + 1) * 1 days;
	// 	auctioneerEmissions.initializeEmissions(timestamp);

	// 	for (uint256 day = 0; day < (auctioneerEmissions.EPOCH_DURATION() * 8); day++) {
	// 		vm.warp(timestamp + 12 hours + (day * 1 days));
	// 		vm.prank(address(auctioneer));
	// 		auctioneerEmissions.allocateAuctionEmissions(block.timestamp, bp);
	// 	}

	// 	for (uint8 epoch = 0; epoch < 8; epoch++) {
	// 		console.log("Epoch %s emissions remaining: %s", epoch, auctioneerEmissions.epochEmissionsRemaining(epoch));
	// 		assertApproxEqAbs(
	// 			auctioneerEmissions.epochEmissionsRemaining(epoch),
	// 			0,
	// 			10,
	// 			string.concat("Epoch ", vm.toString(epoch), " emissions remaining")
	// 		);
	// 	}
	// }
}
