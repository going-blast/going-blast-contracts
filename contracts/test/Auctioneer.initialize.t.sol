// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import { AuctioneerHarness } from "./AuctioneerHarness.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";

contract AuctioneerCreateTest is AuctioneerHelper {
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

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);
	}

	// INITIALIZE

	function test_initialize_RevertWhen_GONotYetReceived() public {
		auctioneer = new AuctioneerHarness(USD, GO, WETH, 1e18, 1e16, 1e18, 20e18);

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
