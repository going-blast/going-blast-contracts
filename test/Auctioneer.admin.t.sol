// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";

contract AuctioneerAdminTest is AuctioneerHelper {
	function setUp() public override {
		super.setUp();
	}

	// SET TREASURY

	function test_updateTreasury() public {
		auctioneer.updateTreasury(treasury2);
		assertEq((treasury2), auctioneer.treasury());
	}
	function test_updateTreasury_ExpectEmit_UpdatedTreasury() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedTreasury(treasury2);
		auctioneer.updateTreasury(treasury2);
	}
	function test_updateTreasury_RevertWhen_TreasuryIsZeroAddress() public {
		vm.expectRevert(ZeroAddress.selector);
		auctioneer.updateTreasury((address(0)));
	}
	function test_updateTreasury_RevertWhen_CallerIsNotOwner() public {
		_expectRevertNotAdmin(address(0));
		vm.prank(address(0));
		auctioneer.updateTreasury(treasury2);
	}

	// Update treasury cut

	function test_updateTreasuryCut() public {
		auctioneer.updateTreasuryCut(5000);
		assertEq(auctioneer.treasuryCut(), 5000);
	}
	function test_updateTreasuryCut_ExpectEmit_UpdatedTreasuryCut() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedTreasuryCut(4000);
		auctioneer.updateTreasuryCut(4000);
	}
	function test_updateTreasuryCut_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updateTreasuryCut(4000);
	}
	function test_updateTreasuryCut_RevertWhen_CutIsTooSteep() public {
		vm.expectRevert(TooSteep.selector);
		auctioneer.updateTreasuryCut(5001);
	}
}
