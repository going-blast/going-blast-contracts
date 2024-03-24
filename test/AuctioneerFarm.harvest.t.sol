// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/IAuctioneerFarm.sol";

contract AuctioneerFarmHarvestTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_initializeFarmVoucherEmissions();
		_createDefaultDay1Auction();
	}

	function _farmDeposit(address user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.deposit(pid, amount, user);
	}

	function _injectFarmUSD(uint256 amount) public {
		vm.startPrank(user1);
		USD.approve(address(farm), amount);
		farm.receiveUsdDistribution(amount);
		vm.stopPrank();
	}

	function test_harvest_ExpectEmit_Harvest() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		uint256 userDebtGo = farm.getPoolUser(goPid, user1).goDebt;
		uint256 userDebtVoucher = farm.getPoolUser(goPid, user1).voucherDebt;
		uint256 userDebtUsd = farm.getPoolUser(goPid, user1).usdDebt;

		uint256 goPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 voucherPerShare = farm.getPoolUpdated(goPid).accVoucherPerShare;
		uint256 usdPerShare = farm.getPoolUpdated(goPid).accUsdPerShare;
		uint256 userStaked = farm.getPoolUser(goPid, user1).amount;
		uint256 expectedGoHarvested = ((goPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtGo;
		uint256 expectedVoucherHarvested = ((voucherPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtVoucher;
		uint256 expectedUsdHarvested = ((usdPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtUsd;

		_expectTokenTransfer(GO, address(farm), user1, expectedGoHarvested);
		_expectTokenTransfer(USD, address(farm), user1, expectedUsdHarvested);

		vm.expectEmit(true, true, true, true);
		emit Harvest(
			user1,
			goPid,
			PendingAmounts({ usd: expectedUsdHarvested, go: expectedGoHarvested, voucher: expectedVoucherHarvested }),
			user1
		);

		vm.prank(user1);
		farm.harvest(goPid, user1);
	}

	function test_harvest_Should_BringGoPerShareCurrent() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		uint256 updatedGoPerShare = farm.getPoolUpdated(goPid).accGoPerShare;

		vm.prank(user1);
		farm.harvest(goPid, user1);

		uint256 stateGoPerShare = farm.getPool(goPid).accGoPerShare;
		assertEq(stateGoPerShare, updatedGoPerShare, "Go Reward per Share brought current");
	}

	function test_harvest_Should_PendingAndHarvestedMatch() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);

		_expectTokenTransfer(GO, address(farm), user1, pending.go);
		_expectTokenTransfer(USD, address(farm), user1, pending.usd);

		vm.prank(user1);
		farm.harvest(goPid, user1);
	}

	function test_harvest_Should_PendingDropTo0AfterHarvest() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);

		assertGt(pending.usd, 0, "Should have some pending USD");
		assertGt(pending.go, 0, "Should have some pending GO");

		vm.prank(user1);
		farm.harvest(goPid, user1);

		pending = farm.pending(goPid, user1);

		assertEq(pending.usd, 0, "Pending USD dropped to 0");
		assertEq(pending.go, 0, "Pending GO dropped to 0");
	}

	function test_harvest_ShouldNot_UpdateStakingData() public {
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);

		assertEq(farm.getPool(goPid).supply, 10e18, "Initial supply = 10");
		assertEq(farm.getPoolUser(goPid, user1).amount, 10e18, "Initial user staked amount 10");

		vm.prank(user1);
		farm.harvest(goPid, user1);

		assertEq(farm.getPool(goPid).supply, 10e18, "Final supply = 10");
		assertEq(farm.getPoolUser(goPid, user1).amount, 10e18, "Final user staked amount 10");
	}

	function test_harvest_Should_UpdateDebts() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1 days);

		// goPerShare
		uint256 updatedGoRewPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 expectedGoPerShare = (_farm_goPerSecond(goPid) *
			1 days *
			farm.REWARD_PRECISION() *
			farm.getPool(goPid).allocPoint) / (farm.getPool(goPid).supply * farm.totalAllocPoint());
		assertEq(updatedGoRewPerShare, expectedGoPerShare, "Go per share updated correctly");

		// usdPerShare
		uint256 expectedUsdPerShare = (100e18 * farm.REWARD_PRECISION() * farm.getPool(goPid).allocPoint) /
			(farm.getPool(goPid).supply * farm.totalAllocPoint());
		assertEq(farm.getPoolUpdated(goPid).accUsdPerShare, expectedUsdPerShare, "Usd Reward per Share matches expected");

		assertEq(farm.getPoolUser(goPid, user1).goDebt, 0, "User1 debt GO not yet initialized");
		assertEq(farm.getPoolUser(goPid, user1).usdDebt, 0, "User1 debt USD not yet initialized");

		vm.prank(user1);
		farm.harvest(goPid, user1);

		// goPerShare updated
		updatedGoRewPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		assertEq(updatedGoRewPerShare, expectedGoPerShare, "Go Reward Per Share updated as part of harvest");

		// User staked
		uint256 expectedUser1Staked = 10e18;
		assertEq(farm.getPoolUser(goPid, user1).amount, expectedUser1Staked, "User staked should match expected");

		// GO debt
		uint256 expectedUser1DebtGO = (expectedUser1Staked * expectedGoPerShare) / farm.REWARD_PRECISION();
		assertEq(farm.getPoolUser(goPid, user1).goDebt, expectedUser1DebtGO, "User1 debt GO matches expected");

		// USD debt
		uint256 expectedUser1DebtUSD = (expectedUser1Staked * expectedUsdPerShare) / farm.REWARD_PRECISION();
		assertEq(farm.getPoolUser(goPid, user1).usdDebt, expectedUser1DebtUSD, "User1 debt USD  matches expected");
	}

	function test_allHarvest() public {
		farm.add(20000, GO_LP);

		_farmDeposit(user1, goPid, 10e18);
		_farmDeposit(user1, goLpPid, 3e18);

		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory pending = farm.allPending(user1);

		assertGt(pending.go, 0, "Has some go to harvest");
		assertGt(pending.voucher, 0, "Has some voucher to harvest");
		assertGt(pending.usd, 0, "Has some usd to harvest");

		uint256 goInit = GO.balanceOf(user1);
		uint256 voucherInit = VOUCHER.balanceOf(user1);
		uint256 usdInit = USD.balanceOf(user1);

		// Expect 2 harvest events (goPid & goLpPid)
		PendingAmounts memory goPoolPending = farm.pending(goPid, user1);
		PendingAmounts memory goLpPoolPending = farm.pending(goLpPid, user1);
		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, goPoolPending, user1);
		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goLpPid, goLpPoolPending, user1);

		vm.prank(user1);
		farm.allHarvest(user1);

		uint256 goFinal = GO.balanceOf(user1);
		uint256 voucherFinal = VOUCHER.balanceOf(user1);
		uint256 usdFinal = USD.balanceOf(user1);

		assertEq(goFinal - goInit, pending.go, "AllHarvested GO should match pending");
		assertEq(voucherFinal - voucherInit, pending.voucher, "AllHarvested VOUCHER should match pending");
		assertEq(usdFinal - usdInit, pending.usd, "AllHarvested USD should match pending");
	}
	function test_allHarvest_to() public {
		_farmDeposit(user1, goPid, 10e18);
		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory pending = farm.allPending(user1);

		assertGt(pending.go, 0, "Has some go to harvest");
		assertGt(pending.voucher, 0, "Has some voucher to harvest");
		assertGt(pending.usd, 0, "Has some usd to harvest");

		uint256 goInit = GO.balanceOf(user2);
		uint256 voucherInit = VOUCHER.balanceOf(user2);
		uint256 usdInit = USD.balanceOf(user2);

		// Expect 2 harvest events (goPid & goLpPid)
		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, pending, user2);

		vm.prank(user1);
		farm.allHarvest(user2);

		uint256 goFinal = GO.balanceOf(user2);
		uint256 voucherFinal = VOUCHER.balanceOf(user2);
		uint256 usdFinal = USD.balanceOf(user2);

		assertEq(goFinal - goInit, pending.go, "user2 AllHarvested GO should match user1 pending");
		assertEq(voucherFinal - voucherInit, pending.voucher, "user2 AllHarvested VOUCHER should match user1 pending");
		assertEq(usdFinal - usdInit, pending.usd, "user2 AllHarvested USD should match user1 pending");
	}

	function test_harvest_to() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmUSD(100e18);
		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);
		_expectTokenTransfer(GO, address(farm), user2, pending.go);
		_expectTokenTransfer(VOUCHER, address(farm), user2, pending.voucher);
		_expectTokenTransfer(USD, address(farm), user2, pending.usd);

		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, pending, user2);

		vm.prank(user1);
		farm.harvest(goPid, user2);
	}
}
