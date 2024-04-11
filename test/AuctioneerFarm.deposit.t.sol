// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/IAuctioneerFarm.sol";

contract AuctioneerFarmDepositTest is AuctioneerHelper, AuctioneerFarmEvents {
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

	function test_deposit_RevertWhen_BadDeposit() public {
		vm.expectRevert(IAuctioneerFarm.BadDeposit.selector);
		vm.prank(user1);
		farm.deposit(goPid, 100e18, user1);
	}

	function test_deposit_RevertWhen_TokenNotApproved() public {
		// SETUP
		vm.prank(user1);
		GO.approve(address(farm), 0);

		// EXECUTE
		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(farm), 0, 20e18));

		vm.prank(user1);
		farm.deposit(goPid, 20e18, user1);
	}

	function test_deposit_RevertWhen_InvalidPid() public {
		XXToken.mint(user1, 50e18);

		vm.expectRevert(IAuctioneerFarm.InvalidPid.selector);

		vm.prank(user1);
		farm.deposit(xxPid, 20e18, user1);
	}

	function test_deposit_ExpectEmit_Deposit() public {
		vm.expectEmit(true, true, true, true);
		emit Deposit(user1, goPid, 5e18, user1);

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);
	}

	function test_deposit_Should_UpdateStakingData() public {
		assertEq(farm.getPool(goPid).supply, 0, "Initial total staked amount 0");
		assertEq(farm.getPoolUser(goPid, user1).amount, 0, "Initial user staked amount 0");

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		assertEq(farm.getPool(goPid).supply, 5e18, "Total staked amount 5e18");
		assertEq(farm.getPoolUser(goPid, user1).amount, 5e18, "User staked amount 5e18");
	}

	function test_deposit_Should_UpdateDebts() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);

		// Add USD
		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1 days);

		// goRewardPerShare
		uint256 updatedGoPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 expectedGoPerShare = (_farm_goPerSecond(goPid) * 1 days * farm.REWARD_PRECISION()) /
			farm.getEqualizedTotalStaked();
		assertEq(updatedGoPerShare, expectedGoPerShare, "Go per share updated correctly");

		// usdRewardPerShare
		uint256 expectedUsdRewardPerShare = (100e18 * farm.getPool(goPid).allocPoint * farm.REWARD_PRECISION()) /
			(farm.getPool(goPid).supply * farm.totalAllocPoint());
		assertEq(farm.getPool(goPid).accUsdPerShare, expectedUsdRewardPerShare, "Usd Reward per Share matches expected");

		assertEq(farm.getPoolUser(goPid, user1).goDebt, 0, "User1 debt GO not yet initialized");
		assertEq(farm.getPoolUser(goPid, user1).usdDebt, 0, "User1 debt USD not yet initialized");

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		// goRewardPerShare updated
		uint256 stateGoRewPerShare = farm.getPool(goPid).accGoPerShare;
		updatedGoPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		assertEq(stateGoRewPerShare, expectedGoPerShare, "Go Reward Per Share updated as part of harvest");

		// User staked
		uint256 expectedUser1Staked = 5e18;
		assertEq(farm.getPoolUser(goPid, user1).amount, expectedUser1Staked, "User staked should match expected");

		// GO debt
		uint256 expectedUser1DebtGO = (expectedUser1Staked * expectedGoPerShare) / farm.REWARD_PRECISION();
		assertEq(farm.getPoolUser(goPid, user1).goDebt, expectedUser1DebtGO, "User1 debt GO matches expected");

		// USD debt
		uint256 expectedUser1DebtUSD = (expectedUser1Staked * expectedUsdRewardPerShare) / farm.REWARD_PRECISION();
		assertEq(farm.getPoolUser(goPid, user1).usdDebt, expectedUser1DebtUSD, "User1 debt USD  matches expected");
	}

	function test_deposit_Should_HarvestPending() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);

		// Add USD
		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		uint256 userDebtGo = farm.getPoolUser(goPid, user1).goDebt;
		uint256 userDebtVoucher = farm.getPoolUser(goPid, user1).voucherDebt;
		uint256 userDebtUsd = farm.getPoolUser(goPid, user1).usdDebt;

		// Add new batch of usd
		_injectFarmUSD(75e18);

		// Warp to emit GO
		vm.warp(block.timestamp + 1.5 days);

		uint256 goRewardPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 voucherRewardPerShare = farm.getPoolUpdated(goPid).accVoucherPerShare;
		uint256 usdRewardPerShare = farm.getPoolUpdated(goPid).accUsdPerShare;
		uint256 userStaked = farm.getPoolUser(goPid, user1).amount;
		uint256 expectedGoHarvested = ((goRewardPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtGo;
		uint256 expectedVoucherHarvested = ((voucherRewardPerShare * userStaked) / farm.REWARD_PRECISION()) -
			userDebtVoucher;
		uint256 expectedUsdHarvested = ((usdRewardPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtUsd;

		_expectTokenTransfer(GO, address(farm), user1, expectedGoHarvested);
		_expectTokenTransfer(USD, address(farm), user1, expectedUsdHarvested);

		vm.expectEmit(true, true, true, true);
		emit Harvest(
			user1,
			goPid,
			PendingAmounts({ go: expectedGoHarvested, voucher: expectedVoucherHarvested, usd: expectedUsdHarvested }),
			user1
		);

		vm.prank(user1);
		farm.deposit(goPid, 1e18, user1);
	}
	function test_deposit_Deposit0_Should_HarvestPending() public {
		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);

		// Add USD
		_injectFarmUSD(100e18);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		uint256 userDebtGo = farm.getPoolUser(goPid, user1).goDebt;
		uint256 userDebtVoucher = farm.getPoolUser(goPid, user1).voucherDebt;
		uint256 userDebtUsd = farm.getPoolUser(goPid, user1).usdDebt;

		// Add new batch of usd
		_injectFarmUSD(75e18);

		// Warp to emit GO
		vm.warp(block.timestamp + 1.5 days);

		uint256 updatedGoPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 updatedVoucherRewPerShare = farm.getPoolUpdated(goPid).accVoucherPerShare;
		uint256 updatedUsdRewPerShare = farm.getPoolUpdated(goPid).accUsdPerShare;
		uint256 userStaked = farm.getPoolUser(goPid, user1).amount;
		uint256 expectedGoHarvested = ((updatedGoPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtGo;
		uint256 expectedVoucherHarvested = ((updatedVoucherRewPerShare * userStaked) / farm.REWARD_PRECISION()) -
			userDebtVoucher;
		uint256 expectedUsdHarvested = ((updatedUsdRewPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtUsd;

		_expectTokenTransfer(GO, address(farm), user1, expectedGoHarvested);
		_expectTokenTransfer(USD, address(farm), user1, expectedUsdHarvested);

		vm.expectEmit(true, true, true, true);
		emit Harvest(
			user1,
			goPid,
			PendingAmounts({ go: expectedGoHarvested, voucher: expectedVoucherHarvested, usd: expectedUsdHarvested }),
			user1
		);

		vm.prank(user1);
		farm.deposit(goPid, 0, user1);
	}

	function test_deposit_to() public {
		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		// Emissions
		_injectFarmUSD(75e18);
		vm.warp(block.timestamp + 1.5 days);

		PendingAmounts memory pending = farm.pending(goPid, user1);

		_expectTokenTransfer(GO, address(farm), user2, pending.go);
		_expectTokenTransfer(VOUCHER, address(farm), user2, pending.voucher);
		_expectTokenTransfer(USD, address(farm), user2, pending.usd);

		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, pending, user2);

		vm.expectEmit(true, true, true, true);
		emit Deposit(user1, goPid, 1e18, user2);

		vm.prank(user1);
		farm.deposit(goPid, 1e18, user2);
	}
}
