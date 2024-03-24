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
		_setupAuctioneerTreasury();

		// _initializeAuctioneerEmissions();
		// _giveUsersTokensAndApprove();
		// _auctioneerUpdateFarm();
		// _initializeFarmEmissions();
		// _createDefaultDay1Auction();
	}

	// INITIALIZE

	function test_initialize_RevertWhen_GONotYetReceived() public {
		_createAndLinkAuctioneers();

		vm.expectRevert(GONotYetReceived.selector);

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
		uint256 startTimestamp = _getNextDay2PMTimestamp();
		auctioneerEmissions.initializeEmissions(startTimestamp);

		assertEq(auctioneerEmissions.startTimestamp(), startTimestamp);

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
}
