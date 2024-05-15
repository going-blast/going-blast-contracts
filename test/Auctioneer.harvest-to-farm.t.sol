// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import "../src/IAuctioneerFarm.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBMath, AuctionViewUtils } from "../src/AuctionUtils.sol";

contract AuctioneerHarvestToFarmTest is AuctioneerHelper, AuctioneerFarmEvents {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	error GoLocked();

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_createDefaultDay1Auction();
	}

	// HARVEST TO FARM

	// [x] Auctioneer - Harvest to farm
	//   [x] Marked as harvested correctly
	//   [x] Deposits in farm correctly
	//	 [x] Harvests farm
	//   [x] Locks deposited go
	//   [x] Transfers go correctly
	//   [x] Unlock timestamp set to max(current unlock, deposit unlock)
	//   [x] Withdrawing GO reverts if locked
	//   [x] Emergency withdrawing GO reverts if locked

	function test_harvestToFarm_HarvestedMarkedAsTrue() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		bool harvested = auctioneerUser.getAuctionUser(0, user1).emissionsHarvested;
		assertEq(harvested, false, "User has not harvested emissions");

		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, true);

		harvested = auctioneerUser.getAuctionUser(0, user1).emissionsHarvested;
		assertEq(harvested, true, "User has harvested emissions");
	}

	function test_depositLockedGo_RevertWhen_NotAuctioneer() public {
		vm.expectRevert(NotAuctioneer.selector);

		vm.prank(user1);
		farm.depositLockedGo(10e18, user1, block.timestamp);
	}

	function test_harvestToFarm_DepositsInFarm() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		uint256 staked = farm.getPoolUser(0, user1).amount;
		assertEq(staked, 0, "User has not staked any GO");

		uint256[] memory auctionsToHarvest = new uint256[](1);
		uint256 harvestableEmissions = getUserLotInfo(0, user1).emissionsEarned;
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, true);

		staked = farm.getPoolUser(0, user1).amount;
		assertEq(staked, harvestableEmissions, "User has staked GO");
	}

	function test_harvestToFarm_DepositsInFarm_LocksGO() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		uint256 goUnlockTimestamp = farm.getPoolUser(0, user1).goUnlockTimestamp;
		assertEq(goUnlockTimestamp, 0, "User has no GO lock");

		uint256[] memory auctionsToHarvest = new uint256[](1);
		uint256 matureTimestamp = getUserLotInfo(0, user1).matureTimestamp;
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, true);

		goUnlockTimestamp = farm.getPoolUser(0, user1).goUnlockTimestamp;
		assertEq(goUnlockTimestamp, matureTimestamp, "GO locked until it would mature");
	}

	function test_harvestToFarm_DepositsInFarm_SetsLockToMaxTimestamp() public {
		// Send GO to auctioneer
		vm.prank(address(auctioneerEmissions));
		GO.safeTransfer(address(auctioneer), 10e18);

		// Deposit locked go
		vm.startPrank(address(auctioneer));
		GO.forceApprove(address(farm), 10e18);
		farm.depositLockedGo(1e18, user1, block.timestamp + 100);
		vm.stopPrank();

		assertEq(farm.getPoolUser(0, user1).goUnlockTimestamp, block.timestamp + 100, "Unlock timestamp set to +100");
		assertEq(farm.getPoolUser(0, user1).amount, 1e18, "User deposited should be 1");

		// Lower unlock timestamp should not update farm unlock timestamp
		vm.prank(address(auctioneer));
		farm.depositLockedGo(1e18, user1, block.timestamp + 50);

		assertEq(
			farm.getPoolUser(0, user1).goUnlockTimestamp,
			block.timestamp + 100,
			"Unlock timestamp should remain +100"
		);
		assertEq(farm.getPoolUser(0, user1).amount, 2e18, "User deposited should be 2");

		// Higher unlock timestamp should update farm unlock timestamp
		vm.prank(address(auctioneer));
		farm.depositLockedGo(1e18, user1, block.timestamp + 150);

		assertEq(
			farm.getPoolUser(0, user1).goUnlockTimestamp,
			block.timestamp + 150,
			"Unlock timestamp should update to +150"
		);
		assertEq(farm.getPoolUser(0, user1).amount, 3e18, "User deposited should be 3");
	}

	function test_harvestToFarm_GOTransferredToFarm() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		uint256 harvestableEmissions = getUserLotInfo(0, user1).emissionsEarned;
		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;

		_expectTokenTransfer(GO, address(auctioneerEmissions), address(auctioneer), harvestableEmissions);
		_expectTokenTransfer(GO, address(auctioneer), address(farm), harvestableEmissions);

		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, true);
	}

	function test_harvestToFarm_HarvestsExistingRewards() public {
		// Prep harvest to farm

		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);
		vm.warp(block.timestamp + 1 days);

		// Prep farm

		// Add shares
		vm.prank(user2);
		farm.deposit(goPid, 10e18, user2);

		// Add USD
		_injectFarmETH(100e18);

		vm.warp(block.timestamp + 1 days);

		vm.prank(user1);
		farm.deposit(goPid, 5e18, user1);

		uint256 userDebtGo = farm.getPoolUser(goPid, user1).goDebt;
		uint256 userDebtVoucher = farm.getPoolUser(goPid, user1).voucherDebt;
		uint256 userDebtEth = farm.getPoolUser(goPid, user1).ethDebt;

		// Add new batch of usd
		_injectFarmETH(75e18);

		// Warp to emit GO
		vm.warp(block.timestamp + 1.5 days);

		uint256 goRewardPerShare = farm.getPoolUpdated(goPid).accGoPerShare;
		uint256 voucherRewardPerShare = farm.getPoolUpdated(goPid).accVoucherPerShare;
		uint256 ethRewardPerShare = farm.getPoolUpdated(goPid).accEthPerShare;
		uint256 userStaked = farm.getPoolUser(goPid, user1).amount;
		uint256 expectedGoHarvested = ((goRewardPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtGo;
		uint256 expectedVoucherHarvested = ((voucherRewardPerShare * userStaked) / farm.REWARD_PRECISION()) -
			userDebtVoucher;
		uint256 expectedEthHarvested = ((ethRewardPerShare * userStaked) / farm.REWARD_PRECISION()) - userDebtEth;

		vm.expectEmit(true, true, true, true);
		emit Harvest(
			address(auctioneer),
			goPid,
			PendingAmounts({ go: expectedGoHarvested, voucher: expectedVoucherHarvested, eth: expectedEthHarvested }),
			user1
		);

		// Harvest
		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, true);
	}

	function test_harvestToFarm_RevertWhen_WithdrawLockedGO() public {
		// Send GO to auctioneer
		vm.prank(address(auctioneerEmissions));
		GO.safeTransfer(address(auctioneer), 10e18);

		// Deposit locked go
		vm.startPrank(address(auctioneer));
		GO.forceApprove(address(farm), 10e18);
		farm.depositLockedGo(1e18, user1, block.timestamp + 100);
		vm.stopPrank();

		assertEq(farm.getPoolUser(0, user1).amount, 1e18, "User deposited should be 1");

		vm.expectRevert(GoLocked.selector);

		vm.prank(user1);
		farm.withdraw(0, 1e18, user1);
	}

	function test_harvestToFarm_RevertWhen_EmergencyWithdrawLockedGO() public {
		// Send GO to auctioneer
		vm.prank(address(auctioneerEmissions));
		GO.safeTransfer(address(auctioneer), 10e18);

		// Deposit locked go
		vm.startPrank(address(auctioneer));
		GO.forceApprove(address(farm), 10e18);
		farm.depositLockedGo(1e18, user1, block.timestamp + 100);
		vm.stopPrank();

		assertEq(farm.getPoolUser(0, user1).amount, 1e18, "User deposited should be 1");

		vm.expectRevert(GoLocked.selector);

		vm.prank(user1);
		farm.emergencyWithdraw(0, user1);
	}
}
