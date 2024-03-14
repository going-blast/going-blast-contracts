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

contract AuctioneerFarmEmissionsTest is AuctioneerHelper, AuctioneerFarmEvents {
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

		// Initialize farm emissions
		farm.initializeEmissions(farmGO, 180 days);
	}

	function _farmDeposit(address user, address token, uint256 amount) public {
		vm.prank(user);
		farm.deposit(token, amount);
	}
	function _farmWithdraw(address user, address token, uint256 amount) public {
		vm.prank(user);
		farm.withdraw(token, amount);
	}
	function _injectFarmUSD(uint256 amount) public {
		vm.prank(user1);
		IERC20(USD).safeTransfer(address(farm), amount);
		farm.receiveUSDDistribution();
	}

	uint256 user1Deposited = 5e18;
	uint256 user2Deposited = 15e18;
	uint256 user3Deposited = 0.75e18;
	uint256 user4Deposited = 2.8e18;
	uint256 totalDeposited = user1Deposited + user2Deposited + user3Deposited + user4Deposited;

	function test_emissions_PendingGOIncreasesProportionally() public {
		_farmDeposit(user1, address(GO), user1Deposited);
		_farmDeposit(user2, address(GO), user2Deposited);
		_farmDeposit(user3, address(GO), user3Deposited);
		_farmDeposit(user4, address(GO), user4Deposited);

		uint256 goPerSecond = farm.goPerSecond();

		uint256 initTimestamp = block.timestamp;
		vm.warp(1 days);
		uint256 secondsPassed = block.timestamp - initTimestamp;

		uint256 emissions = goPerSecond * secondsPassed;
		uint256 user1Emissions = (user1Deposited * emissions) / totalDeposited;
		uint256 user2Emissions = (user2Deposited * emissions) / totalDeposited;
		uint256 user3Emissions = (user3Deposited * emissions) / totalDeposited;
		uint256 user4Emissions = (user4Deposited * emissions) / totalDeposited;

		(, uint256 user1PendingGo) = farm.pending(user1);
		(, uint256 user2PendingGo) = farm.pending(user2);
		(, uint256 user3PendingGo) = farm.pending(user3);
		(, uint256 user4PendingGo) = farm.pending(user4);

		assertApproxEqAbs(user1Emissions, user1PendingGo, 10, "User1 emissions increase proportionally");
		assertApproxEqAbs(user2Emissions, user2PendingGo, 10, "User2 emissions increase proportionally");
		assertApproxEqAbs(user3Emissions, user3PendingGo, 10, "User3 emissions increase proportionally");
		assertApproxEqAbs(user4Emissions, user4PendingGo, 10, "User4 emissions increase proportionally");
	}

	function test_emissions_PendingUSDIncreasesProportionally() public {
		_farmDeposit(user1, address(GO), user1Deposited);
		_farmDeposit(user2, address(GO), user2Deposited);
		_farmDeposit(user3, address(GO), user3Deposited);
		_farmDeposit(user4, address(GO), user4Deposited);

		uint256 emissions = 100e18;
		_injectFarmUSD(emissions);

		uint256 user1Emissions = (user1Deposited * emissions) / totalDeposited;
		uint256 user2Emissions = (user2Deposited * emissions) / totalDeposited;
		uint256 user3Emissions = (user3Deposited * emissions) / totalDeposited;
		uint256 user4Emissions = (user4Deposited * emissions) / totalDeposited;

		(uint256 user1PendingUSD, ) = farm.pending(user1);
		(uint256 user2PendingUSD, ) = farm.pending(user2);
		(uint256 user3PendingUSD, ) = farm.pending(user3);
		(uint256 user4PendingUSD, ) = farm.pending(user4);

		assertApproxEqAbs(user1Emissions, user1PendingUSD, 10, "User1 emissions increase proportionally");
		assertApproxEqAbs(user2Emissions, user2PendingUSD, 10, "User2 emissions increase proportionally");
		assertApproxEqAbs(user3Emissions, user3PendingUSD, 10, "User3 emissions increase proportionally");
		assertApproxEqAbs(user4Emissions, user4PendingUSD, 10, "User4 emissions increase proportionally");
	}

	function test_emissions_EmissionsCanRunOut() public {
		_farmDeposit(user1, address(GO), user1Deposited);

		uint256 goEmissionFinalTimestamp = farm.goEmissionFinalTimestamp();

		vm.warp(goEmissionFinalTimestamp - 30);
		vm.prank(user1);
		farm.harvest();

		(, uint256 user1PendingGo) = farm.pending(user1);
		uint256 user1PrevPendingGo = user1PendingGo;
		for (int256 i = -29; i < 30; i++) {
			vm.warp(uint256(int256(goEmissionFinalTimestamp) + i));
			(, user1PendingGo) = farm.pending(user1);
			// console.log(
			// 	"Pending GO %s, delta %s, timestamp %s",
			// 	user1PendingGo,
			// 	user1PendingGo - user1PrevPendingGo,
			// 	block.timestamp
			// );
			if (block.timestamp > goEmissionFinalTimestamp) {
				assertEq(user1PendingGo - user1PrevPendingGo, 0, "No more emissions");
			} else {
				assertGt(user1PendingGo - user1PrevPendingGo, 0, "No more emissions");
			}
			user1PrevPendingGo = user1PendingGo;
		}

		vm.expectEmit(true, true, true, true);
		emit Harvested(user1, 0, user1PendingGo);

		vm.prank(user1);
		farm.harvest();

		// getUpdatedGoRewardPerShare doesn't continue to increase
		uint256 updatedGoRewardPerShareInit = farm.getUpdatedGoRewardPerShare();
		vm.warp(block.timestamp + 1 hours);
		uint256 updatedGoRewardPerShareFinal = farm.getUpdatedGoRewardPerShare();
		assertEq(updatedGoRewardPerShareInit, updatedGoRewardPerShareFinal, "Updated go reward per share remains the same");

		// Pending doesn't increase
		vm.warp(block.timestamp + 1 hours);
		(, user1PendingGo) = farm.pending(user1);
		assertEq(user1PendingGo, 0, "No more emissions, forever");
	}
}
