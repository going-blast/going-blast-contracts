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

		// _initializeAuctioneer();
		// _giveUsersTokensAndApprove();
		// _auctioneerSetFarm();
		// _initializeFarmEmissions();
		// _createDefaultDay1Auction();
	}

	// INITIALIZE

	function test_initialize_RevertWhen_GONotYetReceived() public {
		auctioneer = new AuctioneerHarness(USD, GO, VOUCHER, WETH, 1e18, 1e16, 1e18, 20e18);

		vm.expectRevert(GONotYetReceived.selector);

		auctioneer.initialize(_getNextDay2PMTimestamp());
	}
	function test_initialize_RevertWhen_AlreadyInitialized() public {
		auctioneer.initialize(_getNextDay2PMTimestamp());

		vm.expectRevert(AlreadyInitialized.selector);

		auctioneer.initialize(_getNextDay2PMTimestamp());
	}

	function test_initialize_ExpectEmit_Initialized() public {
		vm.expectEmit(false, false, false, false);
		emit Initialized();

		auctioneer.initialize(_getNextDay2PMTimestamp());
	}

	function test_initialize_EmissionsSetCorrectly() public {
		uint256 startTimestamp = _getNextDay2PMTimestamp();
		auctioneer.initialize(startTimestamp);

		assertEq(auctioneer.startTimestamp(), startTimestamp);

		assertGt(auctioneer.epochEmissionsRemaining(0), 0);
		assertApproxEqAbs(auctioneer.epochEmissionsRemaining(0), auctioneer.epochEmissionsRemaining(1) * 2, 10);
		assertApproxEqAbs(auctioneer.epochEmissionsRemaining(1), auctioneer.epochEmissionsRemaining(2) * 2, 10);
		assertApproxEqAbs(auctioneer.epochEmissionsRemaining(2), auctioneer.epochEmissionsRemaining(3) * 2, 10);
		assertApproxEqAbs(auctioneer.epochEmissionsRemaining(3), auctioneer.epochEmissionsRemaining(4) * 2, 10);
		assertApproxEqAbs(auctioneer.epochEmissionsRemaining(4), auctioneer.epochEmissionsRemaining(5) * 2, 10);
		assertApproxEqAbs(auctioneer.epochEmissionsRemaining(5), auctioneer.epochEmissionsRemaining(6) * 2, 10);
		assertApproxEqAbs(auctioneer.epochEmissionsRemaining(6), auctioneer.epochEmissionsRemaining(7) * 2, 10);
	}
}
