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
		assertEq(auctioneerAuction.bidCost(), usdDecOffset(1e18));
		assertEq(auctioneerAuction.bidIncrement(), usdDecOffset(1e16));
		assertEq(auctioneerAuction.startingBid(), usdDecOffset(1e18));
		assertEq(auctioneerAuction.privateAuctionRequirement(), 20e18);
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
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updateTreasury(treasury2);
	}

	// SET FARM
	function test_updateFarm() public {
		auctioneer.updateFarm(address(farm));
		assertEq(address(farm), address(auctioneer.auctioneerFarm()));
	}
	function test_updateFarm_ExpectEmit_UpdatedFarm() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedFarm(address(farm));
		auctioneer.updateFarm(address(farm));
	}
	function test_updateFarm_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updateFarm(address(farm));
	}

	// SET TREASURY SPLIT
	function test_updateTreasurySplit() public {
		auctioneerAuction.updateTreasurySplit(5000);
		assertEq(auctioneerAuction.treasurySplit(), 5000);
	}
	function test_updateTreasurySplit_ExpectEmit_UpdatedTreasurySplit() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedTreasurySplit(4000);
		auctioneerAuction.updateTreasurySplit(4000);
	}
	function test_updateTreasurySplit_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneerAuction.updateTreasurySplit(4000);
	}
	function test_updateTreasurySplit_RevertWhen_CutIsTooSteep() public {
		vm.expectRevert(TooSteep.selector);
		auctioneerAuction.updateTreasurySplit(5001);
	}

	// SET FARM
	function test_updatePrivateAuctionRequirement() public {
		auctioneerAuction.updatePrivateAuctionRequirement(25e18);
		assertEq(25e18, auctioneerAuction.privateAuctionRequirement());
	}
	function test_updatePrivateAuctionRequirement_ExpectEmit_UpdatedPrivateAuctionRequirement() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedPrivateAuctionRequirement(25e18);
		auctioneerAuction.updatePrivateAuctionRequirement(25e18);
	}
	function test_updatePrivateAuctionRequirement_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneerAuction.updatePrivateAuctionRequirement(25e18);
	}

	// SET STARTING BID
	function test_updateStartingBid() public {
		auctioneerAuction.updateStartingBid(usdDecOffset(2e18));
		assertEq(usdDecOffset(2e18), auctioneerAuction.startingBid());
	}
	function test_updateStartingBid_ExpectEmit_UpdatedStartingBid() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedStartingBid(usdDecOffset(2e18));
		auctioneerAuction.updateStartingBid(usdDecOffset(2e18));
	}
	function test_updateStartingBid_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneerAuction.updateStartingBid(usdDecOffset(2e18));
	}
	function test_updateStartingBid_RevertWhen_Invalid_TooLow() public {
		vm.expectRevert(Invalid.selector);
		auctioneerAuction.updateStartingBid(usdDecOffset(0.49e18));
	}
	function test_updateStartingBid_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneerAuction.updateStartingBid(usdDecOffset(2.01e18));
	}

	// SET BID COST
	function test_updateBidCost() public {
		auctioneerAuction.updateBidCost(usdDecOffset(0.5e18));
		assertEq(usdDecOffset(0.5e18), auctioneerAuction.bidCost());
	}
	function test_updateBidCost_ExpectEmit_UpdatedBidCost() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedBidCost(usdDecOffset(0.5e18));
		auctioneerAuction.updateBidCost(usdDecOffset(0.5e18));
	}
	function test_updateBidCost_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneerAuction.updateBidCost(usdDecOffset(0.5e18));
	}
	function test_updateBidCost_RevertWhen_Invalid_TooLow() public {
		vm.expectRevert(Invalid.selector);
		auctioneerAuction.updateBidCost(usdDecOffset(0.49e18));
	}
	function test_updateBidCost_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneerAuction.updateBidCost(usdDecOffset(2.01e18));
	}

	// SET EARLY HARVEST TAX
	function test_updateEarlyHarvestTax() public {
		auctioneerEmissions.updateEarlyHarvestTax(7000);
		assertEq(7000, auctioneerEmissions.earlyHarvestTax());
	}
	function test_updateEarlyHarvestTax_ExpectEmit_UpdatedEarlyHarvestTax() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedEarlyHarvestTax(7000);
		auctioneerEmissions.updateEarlyHarvestTax(7000);
	}
	function test_updateEarlyHarvestTax_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneerEmissions.updateEarlyHarvestTax(7000);
	}
	function test_updateEarlyHarvestTax_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneerEmissions.updateEarlyHarvestTax(8001);
	}

	// SET EMISSION TAX DURATION
	function test_updateEmissionTaxDuration() public {
		auctioneerEmissions.updateEmissionTaxDuration(45);
		assertEq(45, auctioneerEmissions.emissionTaxDuration());
	}
	function test_updateEmissionTaxDuration_ExpectEmit_UpdatedEmissionTaxDuration() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedEmissionTaxDuration(45);
		auctioneerEmissions.updateEmissionTaxDuration(45);
	}
	function test_updateEmissionTaxDuration_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneerEmissions.updateEmissionTaxDuration(45);
	}
	function test_updateEmissionTaxDuration_RevertWhen_Invalid_TooHigh() public {
		vm.expectRevert(Invalid.selector);
		auctioneerEmissions.updateEmissionTaxDuration(60 days + 1);
	}
}
