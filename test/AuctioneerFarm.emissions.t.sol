// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/IAuctioneerFarm.sol";

contract AuctioneerFarmEmissionsTest is AuctioneerHelper, AuctioneerFarmEvents {
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

	function _farmDeposit(address payable user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.deposit(pid, amount, user);
	}
	function _farmWithdraw(address payable user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.withdraw(pid, amount, user);
	}

	uint256 public user1Deposited = 5e18;
	uint256 public user2Deposited = 15e18;
	uint256 public user3Deposited = 0.75e18;
	uint256 public user4Deposited = 2.8e18;
	uint256 public totalDeposited = user1Deposited + user2Deposited + user3Deposited + user4Deposited;

	function test_emissions_PendingGOIncreasesProportionally() public {
		_farmDeposit(user1, goPid, user1Deposited);
		_farmDeposit(user2, goPid, user2Deposited);
		_farmDeposit(user3, goPid, user3Deposited);
		_farmDeposit(user4, goPid, user4Deposited);

		uint256 initTimestamp = block.timestamp;
		vm.warp(1 days);
		uint256 secondsPassed = block.timestamp - initTimestamp;

		uint256 emissions = _farm_goPerSecond(goPid) * secondsPassed;
		uint256 user1Emissions = (user1Deposited * emissions) / totalDeposited;
		uint256 user2Emissions = (user2Deposited * emissions) / totalDeposited;
		uint256 user3Emissions = (user3Deposited * emissions) / totalDeposited;
		uint256 user4Emissions = (user4Deposited * emissions) / totalDeposited;

		uint256 user1PendingGo = farm.pending(goPid, user1).go;
		uint256 user2PendingGo = farm.pending(goPid, user2).go;
		uint256 user3PendingGo = farm.pending(goPid, user3).go;
		uint256 user4PendingGo = farm.pending(goPid, user4).go;

		assertApproxEqAbs(user1Emissions, user1PendingGo, 10, "User1 emissions increase proportionally");
		assertApproxEqAbs(user2Emissions, user2PendingGo, 10, "User2 emissions increase proportionally");
		assertApproxEqAbs(user3Emissions, user3PendingGo, 10, "User3 emissions increase proportionally");
		assertApproxEqAbs(user4Emissions, user4PendingGo, 10, "User4 emissions increase proportionally");
	}

	function test_emissions_totalEthDistributed_Increases() public {
		_farmDeposit(user1, goPid, user1Deposited);

		assertEq(farm.totalEthDistributed(), 0, "Total ETH distributed starts at 0");
		_injectFarmETH(100e18);
		assertEq(farm.totalEthDistributed(), 100e18, "Total ETH distributed should increase to 100e18");
	}

	function test_emissions_PendingETHIncreasesProportionally() public {
		_farmDeposit(user1, goPid, user1Deposited);
		_farmDeposit(user2, goPid, user2Deposited);
		_farmDeposit(user3, goPid, user3Deposited);
		_farmDeposit(user4, goPid, user4Deposited);

		uint256 emissions = 100e18;
		_injectFarmETH(emissions);

		uint256 user1Emissions = (user1Deposited * emissions) / totalDeposited;
		uint256 user2Emissions = (user2Deposited * emissions) / totalDeposited;
		uint256 user3Emissions = (user3Deposited * emissions) / totalDeposited;
		uint256 user4Emissions = (user4Deposited * emissions) / totalDeposited;

		uint256 user1PendingETH = farm.pending(goPid, user1).eth;
		uint256 user2PendingETH = farm.pending(goPid, user2).eth;
		uint256 user3PendingETH = farm.pending(goPid, user3).eth;
		uint256 user4PendingETH = farm.pending(goPid, user4).eth;

		assertApproxEqAbs(user1Emissions, user1PendingETH, 10, "User1 emissions increase proportionally");
		assertApproxEqAbs(user2Emissions, user2PendingETH, 10, "User2 emissions increase proportionally");
		assertApproxEqAbs(user3Emissions, user3PendingETH, 10, "User3 emissions increase proportionally");
		assertApproxEqAbs(user4Emissions, user4PendingETH, 10, "User4 emissions increase proportionally");
	}

	function test_emissions_EmissionsCanRunOut() public {
		_farmDeposit(user1, goPid, user1Deposited);

		uint256 goEmissionFinalTimestamp = farm.getEmission(address(GO)).endTimestamp;

		vm.warp(goEmissionFinalTimestamp - 30);
		vm.prank(user1);
		farm.harvest(goPid, user1);

		uint256 user1PendingGo = farm.pending(goPid, user1).go;
		uint256 user1PrevPendingGo = user1PendingGo;
		uint256 user1PendingVoucher = farm.pending(goPid, user1).voucher;
		uint256 user1PrevPendingVoucher = user1PendingVoucher;
		for (int256 i = -29; i < 30; i++) {
			vm.warp(uint256(int256(goEmissionFinalTimestamp) + i));
			user1PendingGo = farm.pending(goPid, user1).go;
			user1PendingVoucher = farm.pending(goPid, user1).voucher;
			if (block.timestamp > goEmissionFinalTimestamp) {
				assertEq(user1PendingGo - user1PrevPendingGo, 0, "No more GO emissions");
				assertEq(user1PendingVoucher - user1PrevPendingVoucher, 0, "No more VOUCHER emissions");
			} else {
				assertGt(user1PendingGo - user1PrevPendingGo, 0, "Still emitting GO");
				assertGt(user1PendingVoucher - user1PrevPendingVoucher, 0, "Still emitting VOUCHER");
			}
			user1PrevPendingGo = user1PendingGo;
			user1PrevPendingVoucher = user1PendingVoucher;
		}

		vm.expectEmit(true, true, true, true);
		emit Harvest(user1, goPid, PendingAmounts({ go: user1PendingGo, voucher: user1PendingVoucher, eth: 0 }), user1);

		vm.prank(user1);
		farm.harvest(goPid, user1);

		// getUpdatedGoPerShare doesn't continue to increase
		uint256 updatedGoPerShareInit = farm.getPoolUpdated(goPid).accGoPerShare;
		vm.warp(block.timestamp + 1 hours);
		uint256 updatedGoPerShareFinal = farm.getPoolUpdated(goPid).accGoPerShare;
		assertEq(updatedGoPerShareInit, updatedGoPerShareFinal, "Updated go reward per share remains the same");

		// Pending doesn't increase
		vm.warp(block.timestamp + 1 hours);
		user1PendingGo = farm.pending(goPid, user1).go;
		assertEq(user1PendingGo, 0, "No more GO emissions, forever");

		// getUpdatedVoucherPerShare doesn't continue to increase
		uint256 updatedVoucherPerShareInit = farm.getPoolUpdated(goPid).accVoucherPerShare;
		vm.warp(block.timestamp + 1 hours);
		uint256 updatedVoucherPerShareFinal = farm.getPoolUpdated(goPid).accVoucherPerShare;
		assertEq(
			updatedVoucherPerShareInit,
			updatedVoucherPerShareFinal,
			"Updated VOUCHER reward per share remains the same"
		);

		// Pending doesn't increase
		vm.warp(block.timestamp + 1 hours);
		user1PendingVoucher = farm.pending(goPid, user1).voucher;
		assertEq(user1PendingVoucher, 0, "No more VOUCHER emissions, forever");
	}
}
