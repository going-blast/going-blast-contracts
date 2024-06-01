// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/AuctioneerFarm.sol";

contract AuctioneerFarmHarvestTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_initializeFarmVoucherEmissions();
		_createDefaultDay1Auction();
	}

	function _farmDeposit(address payable user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.deposit(pid, amount, user);
	}

	function test_harvest_ExpectEmit_Harvest() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1.5 days);

		uint256 userDebtGo = farm.getPoolUser(goPid, user1).goDebt;
		uint256 userDebtVoucher = farm.getPoolUser(goPid, user1).voucherDebt;
		uint256 userDebtEth = farm.getPoolUser(goPid, user1).ethDebt;

		uint256 goPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 voucherPerShare = farm.getPoolUpdated(goPid).accVoucherPerShare;
		uint256 ethPerShare = farm.getPoolUpdated(goPid).accEthPerShare;
		uint256 userStaked = farm.getPoolUser(goPid, user1).amount;
		uint256 expectedGoHarvested = ((goPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtGo;
		uint256 expectedVoucherHarvested = ((voucherPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtVoucher;
		uint256 expectedEthHarvested = ((ethPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtEth;

		_expectTokenTransfer(GO, address(farm), user1, expectedGoHarvested);
		_prepExpectETHTransfer(0, address(farm), user1);

		vm.expectEmit(true, true, true, true);
		emit Harvest(
			user1,
			goPid,
			PendingAmounts({ eth: expectedEthHarvested, go: expectedGoHarvested, voucher: expectedVoucherHarvested }),
			user1
		);

		vm.prank(user1);
		farm.harvest(goPid, user1);

		_expectETHTransfer(0, address(farm), user1, expectedEthHarvested);
	}

	function test_harvest_Should_BringGoPerShareCurrent() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmETH(100e18);

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

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);

		_expectTokenTransfer(GO, address(farm), user1, pending.go);
		_prepExpectETHTransfer(0, address(farm), user1);

		vm.prank(user1);
		farm.harvest(goPid, user1);

		_expectETHTransfer(0, address(farm), user1, pending.eth);
	}

	function test_harvest_Should_PendingDropTo0AfterHarvest() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);

		assertGt(pending.eth, 0, "Should have some pending ETH");
		assertGt(pending.go, 0, "Should have some pending GO");

		vm.prank(user1);
		farm.harvest(goPid, user1);

		pending = farm.pending(goPid, user1);

		assertEq(pending.eth, 0, "Pending ETH dropped to 0");
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

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		// goPerShare
		uint256 updatedGoRewPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 expectedGoPerShare = (_farm_goPerSecond(goPid) *
			1 days *
			farm.REWARD_PRECISION() *
			farm.getPool(goPid).allocPoint) / (farm.getPool(goPid).supply * farm.totalAllocPoint());
		assertEq(updatedGoRewPerShare, expectedGoPerShare, "Go per share updated correctly");

		// ethPerShare
		uint256 expectedEthPerShare = (100e18 * farm.REWARD_PRECISION() * farm.getPool(goPid).allocPoint) /
			(farm.getPool(goPid).supply * farm.totalAllocPoint());
		assertEq(
			farm.getPoolUpdated(goPid).accEthPerShare,
			expectedEthPerShare,
			"Eth Reward per Share matches expected"
		);

		assertEq(farm.getPoolUser(goPid, user1).goDebt, 0, "User1 debt GO not yet initialized");
		assertEq(farm.getPoolUser(goPid, user1).ethDebt, 0, "User1 debt ETH not yet initialized");

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

		// ETH debt
		uint256 expectedUser1DebtETH = (expectedUser1Staked * expectedEthPerShare) / farm.REWARD_PRECISION();
		assertEq(farm.getPoolUser(goPid, user1).ethDebt, expectedUser1DebtETH, "User1 debt ETH  matches expected");
	}

	function test_allHarvest() public {
		farm.add(20000, GO_LP);

		_farmDeposit(user1, goPid, 10e18);
		_farmDeposit(user1, goLpPid, 3e18);

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory pending = farm.allPending(user1);

		assertGt(pending.go, 0, "Has some go to harvest");
		assertGt(pending.voucher, 0, "Has some voucher to harvest");
		assertGt(pending.eth, 0, "Has some eth to harvest");

		uint256 goInit = GO.balanceOf(user1);
		uint256 voucherInit = VOUCHER.balanceOf(user1);
		uint256 ethInit = user1.balance;

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
		uint256 ethFinal = user1.balance;

		assertEq(goFinal - goInit, pending.go, "AllHarvested GO should match pending");
		assertEq(voucherFinal - voucherInit, pending.voucher, "AllHarvested VOUCHER should match pending");
		assertEq(ethFinal - ethInit, pending.eth, "AllHarvested ETH should match pending");
	}
	function test_allHarvest_to() public {
		_farmDeposit(user1, goPid, 10e18);
		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		PendingAmounts memory pending = farm.allPending(user1);

		assertGt(pending.go, 0, "Has some go to harvest");
		assertGt(pending.voucher, 0, "Has some voucher to harvest");
		assertGt(pending.eth, 0, "Has some eth to harvest");

		uint256 goInit = GO.balanceOf(user2);
		uint256 voucherInit = VOUCHER.balanceOf(user2);
		uint256 ethInit = user2.balance;

		// Expect 2 harvest events (goPid & goLpPid)
		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, pending, user2);

		vm.prank(user1);
		farm.allHarvest(user2);

		uint256 goFinal = GO.balanceOf(user2);
		uint256 voucherFinal = VOUCHER.balanceOf(user2);
		uint256 ethFinal = user2.balance;

		assertEq(goFinal - goInit, pending.go, "user2 AllHarvested GO should match user1 pending");
		assertEq(voucherFinal - voucherInit, pending.voucher, "user2 AllHarvested VOUCHER should match user1 pending");
		assertEq(ethFinal - ethInit, pending.eth, "user2 AllHarvested ETH should match user1 pending");
	}

	function test_harvest_to() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		_injectFarmETH(100e18);
		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);
		_expectTokenTransfer(GO, address(farm), user2, pending.go);
		_expectTokenTransfer(VOUCHER, address(farm), user2, pending.voucher);
		_prepExpectETHTransfer(0, address(farm), user2);

		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, pending, user2);

		vm.prank(user1);
		farm.harvest(goPid, user2);

		_expectETHTransfer(0, address(farm), user2, pending.eth);
	}
}
