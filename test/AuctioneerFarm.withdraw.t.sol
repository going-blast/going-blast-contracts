// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/IAuctioneerFarm.sol";

contract AuctioneerFarmWithdrawTest is AuctioneerHelper, AuctioneerFarmEvents {
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

	function test_withdraw_RevertWhen_BadWithdrawal() public {
		vm.expectRevert(IAuctioneerFarm.BadWithdrawal.selector);
		vm.prank(user1);
		farm.withdraw(goPid, 100e18, user1);
	}

	function test_withdraw_ExpectEmit_Withdraw() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		vm.expectEmit(true, true, true, true);
		emit Withdraw(user1, goPid, 5e18, user1);

		vm.prank(user1);
		farm.withdraw(goPid, 5e18, user1);
	}

	function test_withdraw_Should_UpdateStakingData() public {
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);

		assertEq(farm.getPool(goPid).supply, 10e18, "Initial supply = 10");
		assertEq(farm.getPoolUser(goPid, user1).amount, 10e18, "Initial user staked amount 10");

		vm.prank(user1);
		farm.withdraw(goPid, 5e18, user1);

		assertEq(farm.getPool(goPid).supply, 5e18, "Total supply = 5");
		assertEq(farm.getPoolUser(goPid, user1).amount, 5e18, "User staked amount 5e18");
	}

	function test_withdraw_Should_UpdateDebts() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		// goPerShare
		uint256 updatedGoPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 expectedGoPerShare = (_farm_goPerSecond(goPid) * 1 days * farm.REWARD_PRECISION()) /
			farm.getEqualizedTotalStaked();
		assertEq(updatedGoPerShare, expectedGoPerShare, "Go per share updated correctly");

		// ethPerShare
		uint256 expectedEthPerShare = (100e18 * farm.REWARD_PRECISION() * farm.getPool(goPid).allocPoint) /
			(farm.totalAllocPoint() * farm.getPool(goPid).supply);
		assertEq(farm.getPool(goPid).accEthPerShare, expectedEthPerShare, "Eth Reward per Share matches expected");

		assertEq(farm.getPoolUser(goPid, user1).goDebt, 0, "User1 debt GO is 0");
		assertEq(farm.getPoolUser(goPid, user1).ethDebt, 0, "User1 debt ETH is 0");

		vm.prank(user1);
		farm.withdraw(goPid, 5e18, user1);

		// goPerShare updated
		assertEq(farm.getPool(goPid).accGoPerShare, expectedGoPerShare, "Go Reward Per Share updated as part of harvest");

		// User staked
		uint256 expectedUser1Staked = 5e18;
		assertEq(farm.getPoolUser(goPid, user1).amount, expectedUser1Staked, "User staked should match expected");

		// GO debt
		uint256 expectedUser1DebtGO = (expectedUser1Staked * expectedGoPerShare) / farm.REWARD_PRECISION();
		assertEq(farm.getPoolUser(goPid, user1).goDebt, expectedUser1DebtGO, "User1 debt GO matches expected");

		// ETH debt
		uint256 expectedUser1DebtETH = (expectedUser1Staked * expectedEthPerShare) / farm.REWARD_PRECISION();
		assertEq(farm.getPoolUser(goPid, user1).ethDebt, expectedUser1DebtETH, "User1 debt ETH matches expected");
	}

	function test_withdraw_Should_HarvestPending() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		uint256 userDebtGo = farm.getPoolUser(goPid, user1).goDebt;
		uint256 userDebtVoucher = farm.getPoolUser(goPid, user1).voucherDebt;
		uint256 userDebtEth = farm.getPoolUser(goPid, user1).ethDebt;

		// Add new batch of eth
		_injectFarmETH(75e18);

		// Warp to emit GO
		vm.warp(block.timestamp + 1.5 days);

		uint256 goPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 voucherPerShare = farm.getPoolUpdated(goPid).accVoucherPerShare;
		uint256 ethPerShare = farm.getPoolUpdated(goPid).accEthPerShare;
		uint256 userStaked = farm.getPoolUser(goPid, user1).amount;
		uint256 expectedGoHarvested = ((goPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtGo;
		uint256 expectedBidHarvested = ((voucherPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtVoucher;
		uint256 expectedEthHarvested = ((ethPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtEth;

		_expectTokenTransfer(GO, address(farm), user1, expectedGoHarvested);
		_prepExpectETHTransfer(0, address(farm), user1);

		vm.expectEmit(true, true, true, true);
		emit Harvest(
			user1,
			goPid,
			PendingAmounts({ go: expectedGoHarvested, voucher: expectedBidHarvested, eth: expectedEthHarvested }),
			user1
		);

		vm.prank(user1);
		farm.withdraw(goPid, 1e18, user1);

		_expectETHTransfer(0, address(farm), user1, expectedEthHarvested);
	}
	function test_withdraw_Withdraw0_Should_HarvestPending() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		uint256 userDebtGo = farm.getPoolUser(goPid, user1).goDebt;
		uint256 userDebtVoucher = farm.getPoolUser(goPid, user1).voucherDebt;
		uint256 userDebtEth = farm.getPoolUser(goPid, user1).ethDebt;

		// Add new batch of eth
		_injectFarmETH(75e18);

		// Warp to emit GO
		vm.warp(block.timestamp + 1.5 days);

		uint256 goPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 voucherPerShare = farm.getPoolUpdated(goPid).accVoucherPerShare;
		uint256 ethPerShare = farm.getPoolUpdated(goPid).accEthPerShare;
		uint256 userStaked = farm.getPoolUser(goPid, user1).amount;
		uint256 expectedGoHarvested = ((goPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtGo;
		uint256 expectedBidHarvested = ((voucherPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtVoucher;
		uint256 expectedEthHarvested = ((ethPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtEth;

		_expectTokenTransfer(GO, address(farm), user1, expectedGoHarvested);
		_prepExpectETHTransfer(0, address(farm), user1);

		vm.expectEmit(true, true, true, true);
		emit Harvest(
			user1,
			goPid,
			PendingAmounts({ go: expectedGoHarvested, voucher: expectedBidHarvested, eth: expectedEthHarvested }),
			user1
		);

		vm.prank(user1);
		farm.withdraw(goPid, 0, user1);

		_expectETHTransfer(0, address(farm), user1, expectedEthHarvested);
	}

	function test_emergencyWithdraw() public {
		// Add shares
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);

		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		// Expect go to be returned
		_expectTokenTransfer(GO, address(farm), user1, 10e18);

		// Expect Emergency withdraw emit
		vm.expectEmit(true, true, true, true);
		emit EmergencyWithdraw(user1, goPid, 10e18, user1);

		vm.prank(user1);
		farm.emergencyWithdraw(goPid, user1);

		// Data updates
		assertEq(farm.getPool(goPid).supply, 0, "Supply should be removed");
		assertEq(farm.getPoolUser(goPid, user1).amount, 0, "User's amount should be removed");
		assertEq(farm.getPoolUser(goPid, user1).goDebt, 0, "Expect Go debt to be set to 0");
		assertEq(farm.getPoolUser(goPid, user1).voucherDebt, 0, "Expect Voucher debt to be set to 0");
		assertEq(farm.getPoolUser(goPid, user1).ethDebt, 0, "Expect Eth debt to be set to 0");
	}

	function test_emergencyWithdraw_to() public {
		// Add shares
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);

		// Expect go to be returned
		_expectTokenTransfer(GO, address(farm), user2, 10e18);

		// Expect Emergency withdraw emit
		vm.expectEmit(true, true, true, true);
		emit EmergencyWithdraw(user1, goPid, 10e18, user2);

		vm.prank(user1);
		farm.emergencyWithdraw(goPid, user2);
	}

	function test_withdraw_to() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		// Emissions
		_injectFarmETH(75e18);
		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);

		_expectTokenTransfer(GO, address(farm), user2, pending.go);
		_expectTokenTransfer(VOUCHER, address(farm), user2, pending.voucher);
		_prepExpectETHTransfer(0, address(farm), user2);

		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, pending, user2);

		vm.expectEmit(true, true, true, true);
		emit Withdraw(user1, goPid, 1e18, user2);

		vm.prank(user1);
		farm.withdraw(goPid, 1e18, user2);

		_expectETHTransfer(0, address(farm), user2, pending.eth);
	}
}
