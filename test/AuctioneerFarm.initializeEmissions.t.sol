// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/AuctioneerFarm.sol";

contract AuctioneerFarmInitializeEmissionsTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_createDefaultDay1Auction();
	}

	function test_initializeEmissions_RevertWhen_NotEnoughEmissionToken() public {
		uint256 farmGO = GO.balanceOf(address(farm));

		vm.expectRevert(IAuctioneerFarm.NotEnoughEmissionToken.selector);
		farm.initializeEmissions(farmGO + 1e18, 180 days);
	}

	function test_initializeEmissions_ExpectEmit_InitializedGOEmission_SetEmission() public {
		uint256 farmGO = GO.balanceOf(address(farm));
		uint256 expectedGoEmission = farmGO / 180 days;

		vm.expectEmit(true, true, true, true);
		emit SetEmission(address(GO), expectedGoEmission, 180 days);

		_initializeFarmEmissions();
	}

	function test_initializeEmissions_RevertWhen_AlreadyInitializedEmissions() public {
		uint256 farmGO = GO.balanceOf(address(farm));
		_initializeFarmEmissions(farmGO);

		assertEq(farm.initializedEmissions(), true, "Emissions initialized");

		vm.expectRevert(IAuctioneerFarm.AlreadyInitializedEmissions.selector);
		_initializeFarmEmissions(farmGO);
	}

	function test_initializeEmissions_RevertWhen_CallerIsNotOwner() public {
		uint256 farmGO = GO.balanceOf(address(farm));

		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));

		vm.prank(address(0));
		_initializeFarmEmissions(farmGO);
	}

	function test_constructor_goPoolAdded() public {
		uint256 poolsCount = farm.poolLength();
		assertEq(poolsCount, 1, "Go pool added");
		assertEq(address(farm.getPool(goPid).token), address(GO), "GO staking token initialized in data struct");
		assertEq(farm.getPool(goPid).allocPoint, 10000, "Go pool alloc set to 10000");
		assertEq(farm.getPool(goPid).supply, 0, "GO Nothing staked yet");

		assertEq(farm.totalAllocPoint(), 10000, "Total allocation set to 10000");
	}
}
