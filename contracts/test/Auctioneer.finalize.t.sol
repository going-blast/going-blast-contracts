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
import { AuctionUtils } from "../AuctionUtils.sol";

contract AuctioneerFinalizeTest is AuctioneerHelper {
	using SafeERC20 for IERC20;
	using AuctionUtils for Auction;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm(USD, GO);
		auctioneer.setTreasury(treasury);

		// Distribute GO
		GO.safeTransfer(address(auctioneer), (GO.totalSupply() * 6000) / 10000);
		GO.safeTransfer(presale, (GO.totalSupply() * 2000) / 10000);
		GO.safeTransfer(treasury, (GO.totalSupply() * 1000) / 10000);
		GO.safeTransfer(liquidity, (GO.totalSupply() * 500) / 10000);
		uint256 farmGO = (GO.totalSupply() * 500) / 10000;
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
		// Mint & Approve XX for auctioneer
		XXToken.mint(treasury, 100000e18);
		vm.prank(treasury);
		IERC20(address(XXToken)).approve(address(auctioneer), type(uint256).max);
		YYToken.mint(treasury, 100000e18);
		vm.prank(treasury);
		IERC20(address(YYToken)).approve(address(auctioneer), type(uint256).max);

		// Give usd to users
		USD.mint(user1, 10000e18);
		USD.mint(user2, 10000e18);
		USD.mint(user3, 10000e18);
		USD.mint(user4, 10000e18);

		// Users approve auctioneer
		vm.prank(user1);
		USD.approve(address(auctioneer), 10000e18);
		vm.prank(user2);
		USD.approve(address(auctioneer), 10000e18);
		vm.prank(user3);
		USD.approve(address(auctioneer), 10000e18);
		vm.prank(user4);
		USD.approve(address(auctioneer), 10000e18);

		AuctionParams[] memory params = new AuctionParams[](2);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		// Create multi token auction
		params[1] = _getMultiTokenSingleAuctionParams();

		// Create single token + nfts auction
		auctioneer.createDailyAuctions(params);

		// Initialize farm emissions
		farm.initializeEmissions(farmGO, 180 days);
	}

	function test_winning_finalizeAuction_RevertWhen_AuctionStillRunning() public {
		vm.expectRevert(AuctionStillRunning.selector);
		auctioneer.finalizeAuction(0);
	}

	function test_winning_finalizeAuction_NotRevertWhen_AuctionAlreadyFinalized() public {
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);
		auctioneer.finalizeAuction(0);

		auctioneer.finalizeAuction(0);
	}

	function test_finalize_finalizeAuction_ExpectEmit_AuctionFinalized() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);

		vm.prank(user1);
		auctioneer.finalizeAuction(0);
	}

	function test_finalize_finalizeAuction_ExpectState_AuctionMarkedAsFinalized() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		auctioneer.finalizeAuction(0);

		assertEq(auctioneer.getAuction(0).finalized, true, "Auction marked finalized");
	}

	function test_finalize_claimAuctionLot_ExpectEmit_AuctionFinalized() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);

		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);
	}

	function testFail_finalize_claimAuctionLot_alreadyFinalized_NotExpectEmit_AuctionFinalized() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		// Finalize auction
		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);

		vm.prank(sender);
		auctioneer.finalizeAuction(0);

		// User claiming lot should not emit
		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);

		// Should revert
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);
	}

	function test_finalizeAuction_TransferEmissionsToTreasury() public {
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		uint256 treasuryGOInit = GO.balanceOf(treasury);
		uint256 expectedEmission = auctioneer.getAuction(0).emissions.treasuryEmission;

		auctioneer.finalizeAuction(0);

		assertEq(GO.balanceOf(treasury), treasuryGOInit + expectedEmission, "Treasury receives GO emissions from auction");
	}

	function test_finalizeAuction_Should_DistributeLotRevenue_RevenueLessThanLotValue() public {
		// Set farm
		auctioneer.setFarm(address(farm));

		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		uint256 revenue = auctioneer.getAuction(0).bidData.sum;
		uint256 lotValue = auctioneer.getAuction(0).rewards.estimatedValue;
		assertLt(revenue, lotValue, "Validate revenue < lotValue");

		uint256 treasuryUSDInit = USD.balanceOf(treasury);
		uint256 farmUSDInit = USD.balanceOf(address(farm));

		// Claim
		auctioneer.finalizeAuction(0);

		// Treasury should receive full lot value
		uint256 treasuryUSDFinal = USD.balanceOf(treasury);
		uint256 farmUSDFinal = USD.balanceOf(address(farm));

		assertEq(treasuryUSDFinal - treasuryUSDInit, revenue, "Treasury should receive 100% of revenue");
		assertEq(farmUSDFinal, farmUSDInit, "Farm should receive nothing");
	}

	function test_finalizeAuction_Should_DistributeLotRevenue_RevenueLessThan110PercLotValue() public {
		// Set farm
		auctioneer.setFarm(address(farm));

		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_multibid(user2, 580);
		_multibid(user3, 1520);
		_multibid(user4, 960);
		_multibid(user1, 1100);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		uint256 revenue = auctioneer.getAuction(0).bidData.sum;
		uint256 lotValue = auctioneer.getAuction(0).rewards.estimatedValue;
		assertGt(revenue, lotValue, "Validate revenue > lotValue");
		assertLt(revenue, (lotValue * 110) / 100, "Validate revenue < 110% lotValue");

		uint256 treasuryUSDInit = USD.balanceOf(treasury);
		uint256 farmUSDInit = USD.balanceOf(address(farm));

		// Claim
		auctioneer.finalizeAuction(0);

		// Treasury should receive full lot value
		uint256 treasuryUSDFinal = USD.balanceOf(treasury);
		uint256 farmUSDFinal = USD.balanceOf(address(farm));

		assertEq(treasuryUSDFinal - treasuryUSDInit, revenue, "Treasury should receive 100% of revenue");
		assertEq(farmUSDFinal, farmUSDInit, "Farm should receive nothing");
	}

	function _farmDeposit() public {
		vm.prank(presale);
		GO.transfer(user1, 10e18);
		vm.prank(user1);
		GO.approve(address(farm), 10e18);
		vm.prank(user1);
		farm.deposit(address(GO), 10e18);
	}

	function test_finalizeAuction_Should_DistributeLotRevenue_RevenueGreaterThanLotValue() public {
		// Set farm
		auctioneer.setFarm(address(farm));

		// Deposit some non zero value into farm to prevent distribution fallback
		_farmDeposit();

		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_multibid(user2, 1580);
		_multibid(user3, 1520);
		_multibid(user4, 1960);
		_multibid(user1, 1100);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		uint256 revenue = auctioneer.getAuction(0).bidData.sum;
		uint256 lotValue = auctioneer.getAuction(0).rewards.estimatedValue;
		uint256 lotValue110Perc = (lotValue * 110) / 100;
		assertGt(revenue, lotValue110Perc, "Validate revenue > 110% lotValue");

		uint256 treasurySplit = auctioneer.treasurySplit();
		uint256 profit = revenue - lotValue110Perc;
		uint256 treasuryExpectedDisbursement = lotValue110Perc + ((profit * treasurySplit) / 10000);
		uint256 farmExpectedDisbursement = (profit * (10000 - treasurySplit)) / 10000;

		uint256 treasuryUSDInit = USD.balanceOf(treasury);
		uint256 farmUSDInit = USD.balanceOf(address(farm));

		// Claim
		auctioneer.finalizeAuction(0);

		uint256 treasuryUSDFinal = USD.balanceOf(treasury);
		uint256 farmUSDFinal = USD.balanceOf(address(farm));

		assertEq(treasuryUSDFinal - treasuryUSDInit, treasuryExpectedDisbursement, "Treasury should receive share");
		assertEq(farmUSDFinal - farmUSDInit, farmExpectedDisbursement, "Farm should receive share");
	}
}
