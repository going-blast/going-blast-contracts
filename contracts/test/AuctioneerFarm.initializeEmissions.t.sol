// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";
import "../IAuctioneerFarm.sol";

contract AuctioneerFarmInitializeEmissionsTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	uint256 public farmGO;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm(USD, GO, VOUCHER);
		auctioneer.setTreasury(treasury);

		// Distribute GO
		GO.safeTransfer(address(auctioneer), (GO.totalSupply() * 6000) / 10000);
		GO.safeTransfer(presale, (GO.totalSupply() * 2000) / 10000);
		GO.safeTransfer(treasury, (GO.totalSupply() * 1000) / 10000);
		GO.safeTransfer(liquidity, (GO.totalSupply() * 500) / 10000);
		farmGO = (GO.totalSupply() * 500) / 10000;
		GO.safeTransfer(address(farm), farmGO);

		// Initialize after receiving GO token
		auctioneer.initialize(_getNextDay2PMTimestamp());

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);

		// Give usd to users
		USD.mint(user1, 1000e18);
		USD.mint(user2, 1000e18);
		USD.mint(user3, 1000e18);
		USD.mint(user4, 1000e18);

		// Users approve auctioneer
		vm.prank(user1);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user2);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user3);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user4);
		USD.approve(address(auctioneer), 1000e18);

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);
	}

	function test_initializeEmissions_RevertWhen_NotEnoughEmissionToken() public {
		vm.expectRevert(IAuctioneerFarm.NotEnoughEmissionToken.selector);
		farm.initializeEmissions(farmGO + 1e18, 180 days);
	}

	function test_initializeEmissions_ExpectEmit_InitializedGOEmission_AddedStakingToken() public {
		uint256 expectedGoEmission = farmGO / 180 days;

		vm.expectEmit(true, true, true, true);
		emit SetEmission(address(GO), expectedGoEmission, 180 days);

		farm.initializeEmissions(farmGO, 180 days);
	}

	function test_initializeEmissions_RevertWhen_AlreadyInitializedEmissions() public {
		farm.initializeEmissions(farmGO, 180 days);

		vm.expectRevert(IAuctioneerFarm.AlreadyInitializedEmissions.selector);
		farm.initializeEmissions(farmGO, 180 days);
	}

	function test_initializeEmissions_RevertWhen_CallerIsNotOwner() public {
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(0)));

		vm.prank(address(0));
		farm.initializeEmissions(farmGO, 180 days);
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
