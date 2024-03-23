// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/IAuctioneerFarm.sol";

contract AuctioneerFarmRunesTest is AuctioneerHelper, AuctioneerFarmEvents {
	using SafeERC20 for IERC20;

	uint256 public farmGO;

	function setUp() public override {
		super.setUp();

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

		for (uint8 i = 0; i < 4; i++) {
			address user = i == 0
				? user1
				: i == 1
					? user2
					: i == 2
						? user3
						: user4;

			// Give tokens
			vm.prank(presale);
			GO.transfer(user, 50e18);
			USD.mint(user, 1000e18);
			GO_LP.mint(user, 50e18);
			XXToken.mint(user, 50e18);
			YYToken.mint(user, 50e18);

			// Approve
			vm.startPrank(user);
			USD.approve(address(auctioneer), 1000e18);
			GO.approve(address(farm), 1000e18);
			GO_LP.approve(address(farm), 1000e18);
			XXToken.approve(address(farm), 1000e18);
			YYToken.approve(address(farm), 1000e18);
			vm.stopPrank();
		}

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		// Initialize farm emissions
		farm.initializeEmissions(farmGO, 180 days);

		// Initialize farm voucher emission
		VOUCHER.mint(address(farm), 100e18 * 180 days);
		farm.setVoucherEmissions(100e18 * 180 days, 180 days);
	}

	function _farmDeposit(address user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.deposit(pid, amount, user);
	}
	function _farmWithdraw(address user, uint256 pid, uint256 amount) public {
		vm.prank(user);
		farm.withdraw(pid, amount, user);
	}
	function _injectFarmUSD(uint256 amount) public {
		vm.startPrank(user1);
		USD.approve(address(farm), amount);
		farm.receiveUsdDistribution(amount);
		vm.stopPrank();
	}

	uint256 public user1Deposited = 5e18;
	uint256 public user2Deposited = 15e18;
	uint256 public user3Deposited = 0.75e18;
	uint256 public user4Deposited = 2.8e18;
	uint256 public totalDeposited = user1Deposited + user2Deposited + user3Deposited + user4Deposited;

	// [ ] validate number of runes = 0 | 2-5
	// [ ] validate no duplicate runeSymbols
	// [ ] uint8 > max wraps around
	// [ ] runes added correctly to auction data from params
	// 		[ ] 0 runes added correctly, multiple runes added correctly
	// [ ] Auction.hasRunes is correct
	// [ ] Rune symbols must be >= 1
	// [ ] Users bid options rune must be from 0 - runes length - 1, 0 if no runes
	// [ ] User can't switch rune
	// [ ] User count of selected rune increased when user places first bid, does not increase on subsequent bids
	// [ ] Users rune is set correctly
	// [ ] Auction not added to claimable lots if no emissions from the auction
	// [ ] Auction bidding data, bidRune set
	// [ ] User is winner: if auction has rune, winning rune matches user's rune, else winning user matches msg.sender
	// [ ] User cannot claim winnings multiple times, both with and without runes
	// [ ] userShareOfLot: 100% (1e18) if winner without runes, user.bids / rune.bids if with runes
	// [ ] Receives userShareOfLot % of lot
	// [ ] Pays userShareOfLot % of lot price
	// [ ] Distribute userShareOfLot % of lot price as profit
	// [ ] Auction cannot have both runes and nfts

	function test_runes_RevertWhen_InvalidNumberOfRuneSymbols() public {}

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

	function test_emissions_PendingUSDIncreasesProportionally() public {
		_farmDeposit(user1, goPid, user1Deposited);
		_farmDeposit(user2, goPid, user2Deposited);
		_farmDeposit(user3, goPid, user3Deposited);
		_farmDeposit(user4, goPid, user4Deposited);

		uint256 emissions = 100e18;
		_injectFarmUSD(emissions);

		uint256 user1Emissions = (user1Deposited * emissions) / totalDeposited;
		uint256 user2Emissions = (user2Deposited * emissions) / totalDeposited;
		uint256 user3Emissions = (user3Deposited * emissions) / totalDeposited;
		uint256 user4Emissions = (user4Deposited * emissions) / totalDeposited;

		uint256 user1PendingUSD = farm.pending(goPid, user1).usd;
		uint256 user2PendingUSD = farm.pending(goPid, user2).usd;
		uint256 user3PendingUSD = farm.pending(goPid, user3).usd;
		uint256 user4PendingUSD = farm.pending(goPid, user4).usd;

		assertApproxEqAbs(user1Emissions, user1PendingUSD, 10, "User1 emissions increase proportionally");
		assertApproxEqAbs(user2Emissions, user2PendingUSD, 10, "User2 emissions increase proportionally");
		assertApproxEqAbs(user3Emissions, user3PendingUSD, 10, "User3 emissions increase proportionally");
		assertApproxEqAbs(user4Emissions, user4PendingUSD, 10, "User4 emissions increase proportionally");
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
		emit Harvest(user1, goPid, PendingAmounts({ go: user1PendingGo, voucher: user1PendingVoucher, usd: 0 }), user1);

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
