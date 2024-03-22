// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";

contract AuctioneerAdminTest is AuctioneerHelper {
	function setUp() public override {
		super.setUp();
	}

	function test_initialConditions() public {
		assertEq(address(USD), address(auctioneer.USD()));
		assertEq(address(GO), address(auctioneer.GO()));
		assertEq(auctioneer.bidCost(), 1e18);
		assertEq(auctioneer.bidIncrement(), 1e16);
		assertEq(auctioneer.startingBid(), 1e18);
		assertEq(auctioneer.privateAuctionRequirement(), 20e18);
	}

	// SET TREASURY

	function test_setTreasury() public {
		auctioneer.setTreasury(treasury2);
		assertEq((treasury2), auctioneer.treasury());
	}
	function test_setTreasury_ExpectEmit_UpdatedTreasury() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedTreasury(treasury2);
		auctioneer.setTreasury(treasury2);
	}
	function test_setTreasury_RevertWhen_TreasuryIsZeroAddress() public {
		vm.expectRevert(ZeroAddress.selector);
		auctioneer.setTreasury((address(0)));
	}
	function test_setTreasury_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.setTreasury(treasury2);
	}

	// SET FARM
	function test_setFarm() public {
		auctioneer.setFarm(address(farm));
		assertEq(address(farm), auctioneer.farm());
	}
	function test_setFarm_ExpectEmit_UpdatedFarm() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedFarm(address(farm));
		auctioneer.setFarm(address(farm));
	}
	function test_setFarm_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.setFarm(address(farm));
	}

	// SET TREASURY SPLIT
	function test_setTreasurySplit() public {
		auctioneer.setTreasurySplit(5000);
		assertEq(auctioneer.treasurySplit(), 5000);
	}
	function test_setTreasurySplit_ExpectEmit_UpdatedTreasurySplit() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedTreasurySplit(4000);
		auctioneer.setTreasurySplit(4000);
	}
	function test_setTreasurySplit_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.setTreasurySplit(4000);
	}
	function test_setTreasurySplit_RevertWhen_CutIsTooSteep() public {
		vm.expectRevert(TooSteep.selector);
		auctioneer.setTreasurySplit(5001);
	}

	// SET FARM
	function test_updatePrivateAuctionRequirement() public {
		auctioneer.updatePrivateAuctionRequirement(25e18);
		assertEq(25e18, auctioneer.privateAuctionRequirement());
	}
	function test_updatePrivateAuctionRequirement_ExpectEmit_UpdatedPrivateAuctionRequirement() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedPrivateAuctionRequirement(25e18);
		auctioneer.updatePrivateAuctionRequirement(25e18);
	}
	function test_updatePrivateAuctionRequirement_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updatePrivateAuctionRequirement(25e18);
	}

	// SET STARTING BID
	function test_updateStartingBid() public {
		auctioneer.updateStartingBid(2e18);
		assertEq(2e18, auctioneer.startingBid());
	}
	function test_updateStartingBid_ExpectEmit_UpdatedStartingBid() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedStartingBid(2e18);
		auctioneer.updateStartingBid(2e18);
	}
	function test_updateStartingBid_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updateStartingBid(2e18);
	}
	function test_updateStartingBid_RevertWhen_Invalid_TooLow() public {
		vm.expectRevert(Invalid.selector);
		auctioneer.updateStartingBid(4e17);
	}
	function test_updateStartingBid_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneer.updateStartingBid(21e17);
	}

	// SET BID COST
	function test_updateBidCost() public {
		auctioneer.updateBidCost(5e17);
		assertEq(5e17, auctioneer.bidCost());
	}
	function test_updateBidCost_ExpectEmit_UpdatedBidCost() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedBidCost(5e17);
		auctioneer.updateBidCost(5e17);
	}
	function test_updateBidCost_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updateBidCost(5e17);
	}
	function test_updateBidCost_RevertWhen_Invalid_TooLow() public {
		vm.expectRevert(Invalid.selector);
		auctioneer.updateBidCost(4e17);
	}
	function test_updateBidCost_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneer.updateBidCost(21e17);
	}

	// SET EARLY HARVEST TAX
	function test_updateEarlyHarvestTax() public {
		auctioneer.updateEarlyHarvestTax(7000);
		assertEq(7000, auctioneer.earlyHarvestTax());
	}
	function test_updateEarlyHarvestTax_ExpectEmit_UpdatedEarlyHarvestTax() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedEarlyHarvestTax(7000);
		auctioneer.updateEarlyHarvestTax(7000);
	}
	function test_updateEarlyHarvestTax_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updateEarlyHarvestTax(7000);
	}
	function test_updateEarlyHarvestTax_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneer.updateEarlyHarvestTax(8001);
	}

	// SET EMISSION TAX DURATION
	function test_updateEmissionTaxDuration() public {
		auctioneer.updateEmissionTaxDuration(45);
		assertEq(45, auctioneer.emissionTaxDuration());
	}
	function test_updateEmissionTaxDuration_ExpectEmit_UpdatedEmissionTaxDuration() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedEmissionTaxDuration(45);
		auctioneer.updateEmissionTaxDuration(45);
	}
	function test_updateEmissionTaxDuration_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updateEmissionTaxDuration(45);
	}
	function test_updateEmissionTaxDuration_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneer.updateEmissionTaxDuration(60 days + 1);
	}
}
