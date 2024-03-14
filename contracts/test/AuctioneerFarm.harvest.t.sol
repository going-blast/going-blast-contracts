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

contract AuctioneerFarmHarvestTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	uint256 public farmGO;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm(USD, GO);
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

		// Initialize farm after receiving GO token
		farm.initializeEmissions(farmGO, 180 days);

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);

		// Give GO to users to deposit / make LP
		vm.startPrank(presale);
		GO.transfer(user1, 50e18);
		GO.transfer(user2, 50e18);
		GO.transfer(user3, 50e18);
		GO.transfer(user4, 50e18);
		vm.stopPrank();

		// Give usd to users
		USD.mint(user1, 1000e18);
		USD.mint(user2, 1000e18);
		USD.mint(user3, 1000e18);
		USD.mint(user4, 1000e18);

		// Users approve auctioneer and farm

		vm.startPrank(user1);
		USD.approve(address(auctioneer), 1000e18);
		GO.approve(address(farm), 1000e18);
		GO_LP.approve(address(farm), 1000e18);
		vm.stopPrank();

		vm.startPrank(user2);
		USD.approve(address(auctioneer), 1000e18);
		GO.approve(address(farm), 1000e18);
		GO_LP.approve(address(farm), 1000e18);
		vm.stopPrank();

		vm.startPrank(user3);
		USD.approve(address(auctioneer), 1000e18);
		GO.approve(address(farm), 1000e18);
		GO_LP.approve(address(farm), 1000e18);
		vm.stopPrank();

		vm.startPrank(user4);
		USD.approve(address(auctioneer), 1000e18);
		GO.approve(address(farm), 1000e18);
		GO_LP.approve(address(farm), 1000e18);
		vm.stopPrank();

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);
	}

	// [x] Updates users debts
	// [x] Emits events
	// [ ] Not transfer if pending is 0
	// [x] Harvested matches pending
	// [x] goPerShare brought current

	function _injectFarmUSD(uint256 amount) public {
		vm.startPrank(user1);
		USD.approve(address(farm), amount);
		farm.receiveUSDDistribution(amount);
		vm.stopPrank();
	}

	function test_harvest_ExpectEmit_Harvested() public {
		vm.prank(user1);
		farm.deposit(address(GO), 5e18);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		uint256 userDebtGO = farm.userDebtGO(user1);
		uint256 userDebtUSD = farm.userDebtUSD(user1);

		uint256 goRewardPerShare = farm.getUpdatedGoRewardPerShare();
		uint256 usdRewardPerShare = farm.usdRewardPerShare();
		uint256 userStaked = farm.getEqualizedUserStaked(user1);
		uint256 expectedGoHarvested = ((goRewardPerShare * userStaked) - userDebtGO) / farm.REWARD_PRECISION();
		uint256 expectedUsdHarvested = ((usdRewardPerShare * userStaked) - userDebtUSD) / farm.REWARD_PRECISION();

		_expectTokenTransfer(USD, address(farm), user1, expectedUsdHarvested);
		_expectTokenTransfer(GO, address(farm), user1, expectedGoHarvested);

		vm.expectEmit(true, true, true, true);
		emit Harvested(user1, expectedUsdHarvested, expectedGoHarvested);

		vm.prank(user1);
		farm.harvest();
	}

	function test_harvest_Should_BringGoPerShareCurrent() public {
		vm.prank(user1);
		farm.deposit(address(GO), 5e18);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		uint256 updatedGoRewardPerShare = farm.getUpdatedGoRewardPerShare();

		vm.prank(user1);
		farm.harvest();

		assertEq(farm.goRewardPerShare(), updatedGoRewardPerShare, "Go Reward per Share brought current");
	}

	function test_harvest_Should_PendingAndHarvestedMatch() public {
		vm.prank(user1);
		farm.deposit(address(GO), 5e18);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		(uint256 pendingUSD, uint256 pendingGO) = farm.pending(user1);

		_expectTokenTransfer(USD, address(farm), user1, pendingUSD);
		_expectTokenTransfer(GO, address(farm), user1, pendingGO);

		vm.prank(user1);
		farm.harvest();
	}

	function test_harvest_Should_PendingDropTo0AfterHarvest() public {
		vm.prank(user1);
		farm.deposit(address(GO), 5e18);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		(uint256 pendingUSD, uint256 pendingGO) = farm.pending(user1);

		assertGt(pendingUSD, 0, "Should have some pending USD");
		assertGt(pendingGO, 0, "Should have some pending GO");

		vm.prank(user1);
		farm.harvest();

		(pendingUSD, pendingGO) = farm.pending(user1);

		assertEq(pendingUSD, 0, "Pending USD dropped to 0");
		assertEq(pendingGO, 0, "Pending GO dropped to 0");
	}

	function test_harvest_ShouldNot_UpdateStakingData() public {
		vm.prank(user1);
		farm.deposit(address(GO), 10e18);

		assertEq(farm.getStakingTokenData(address(GO)).total, 10e18, "Initial total staked amount 10");
		assertEq(farm.getStakingTokenUserStaked(address(GO), user1), 10e18, "Initial user staked amount 10");

		vm.prank(user1);
		farm.harvest();

		assertEq(farm.getStakingTokenData(address(GO)).total, 10e18, "Final total staked amount 10");
		assertEq(farm.getStakingTokenUserStaked(address(GO), user1), 10e18, "Final user staked amount 10");
	}

	function test_harvest_Should_UpdateDebts() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(address(GO), 10e18);
		vm.prank(user1);
		farm.deposit(address(GO), 10e18);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1 days);

		// goRewardPerShare
		uint256 expectedGoRewardPerShare = (farm.goPerSecond() * 1 days * farm.REWARD_PRECISION()) /
			farm.getEqualizedTotalStaked();
		assertEq(farm.getUpdatedGoRewardPerShare(), expectedGoRewardPerShare, "Go per share updated correctly");

		// usdRewardPerShare
		uint256 expectedUsdRewardPerShare = (100e18 * farm.REWARD_PRECISION()) / farm.getEqualizedTotalStaked();
		assertEq(farm.usdRewardPerShare(), expectedUsdRewardPerShare, "Usd Reward per Share matches expected");

		assertEq(farm.userDebtGO(user1), 0, "User1 debt GO not yet initialized");
		assertEq(farm.userDebtUSD(user1), 0, "User1 debt USD not yet initialized");

		vm.prank(user1);
		farm.harvest();

		// goRewardPerShare updated
		assertEq(farm.goRewardPerShare(), expectedGoRewardPerShare, "Go Reward Per Share updated as part of harvest");

		// User staked
		uint256 expectedUser1Staked = 10e18;
		assertEq(farm.getEqualizedUserStaked(user1), expectedUser1Staked, "User staked should match expected");

		// GO debt
		uint256 expectedUser1DebtGO = expectedUser1Staked * expectedGoRewardPerShare;
		assertEq(farm.userDebtGO(user1), expectedUser1DebtGO, "User1 debt GO matches expected");

		// USD debt
		uint256 expectedUser1DebtUSD = expectedUser1Staked * expectedUsdRewardPerShare;
		assertEq(farm.userDebtUSD(user1), expectedUser1DebtUSD, "User1 debt USD  matches expected");
	}
}
