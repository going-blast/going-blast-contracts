// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { IWETH, WETH9 } from "../WETH9.sol";

contract AuctioneerAdminTest is AuctioneerHelper, Test, AuctioneerEvents {
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
		vm.expectEmit(true, false, false, false);
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
		vm.expectEmit(true, false, false, false);
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
		vm.expectEmit(true, false, false, false);
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
		vm.expectEmit(true, false, false, false);
		emit UpdatedPrivateAuctionRequirement(25e18);
		auctioneer.updatePrivateAuctionRequirement(25e18);
	}
	function test_updatePrivateAuctionRequirement_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));
		vm.prank(address(0));
		auctioneer.updatePrivateAuctionRequirement(25e18);
	}
}
