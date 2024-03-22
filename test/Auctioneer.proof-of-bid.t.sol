// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionUtils } from "../src/AuctionUtils.sol";

contract AuctioneerProofOfBidTest is AuctioneerHelper {
	using SafeERC20 for IERC20;
	using AuctionUtils for Auction;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm(USD, GO, VOUCHER);
		auctioneer.setTreasury(treasury);

		// Distribute GO
		GO.safeTransfer(address(auctioneer), (GO.totalSupply() * 6000) / 10000);
		GO.safeTransfer(presale, (GO.totalSupply() * 2000) / 10000);
		GO.safeTransfer(treasury, (GO.totalSupply() * 1000) / 10000);
		GO.safeTransfer(liquidity, (GO.totalSupply() * 500) / 10000);
		GO.safeTransfer(address(farm), (GO.totalSupply() * 500) / 10000);

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

		AuctionParams[] memory params = new AuctionParams[](1);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();

		// Create single token + nfts auction
		auctioneer.createDailyAuctions(params);
	}

	function test_proofOfBid_createSingleAuction_EmissionScalesWithBP() public {
		uint256 timestamp = _getDayInFuture2PMTimestamp(3);
		EpochData memory epochData = auctioneer.exposed_getEpochDataAtTimestamp(timestamp);

		uint256 bp10000Emission = auctioneer.exposed_getEmissionForAuction(timestamp, 10000);
		assertEq(
			bp10000Emission,
			epochData.emissionsRemaining / epochData.daysRemaining,
			"Should give share of remaining emissions"
		);

		uint256 bp20000Emission = auctioneer.exposed_getEmissionForAuction(timestamp, 20000);
		assertEq(
			bp20000Emission,
			2 * (epochData.emissionsRemaining / epochData.daysRemaining),
			"Should give double share of remaining emissions"
		);

		assertEq(bp10000Emission * 2, bp20000Emission, "Doubling bp should double emissions");

		uint256 bp0Emission = auctioneer.exposed_getEmissionForAuction(timestamp, 0);
		assertEq(bp0Emission, 0, "0 BP should give 0 emissions");
	}
	function test_proofOfBid_createSingleAuction_EmissionsMatchExpected() public {
		uint256 timestamp = _getDayInFuture2PMTimestamp(3);

		// BP 10000
		uint256 bp10000Emission = auctioneer.exposed_getEmissionForAuction(timestamp, 10000);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = timestamp;
		params[0].emissionBP = 10000;
		auctioneer.createDailyAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;

		Auction memory auction = auctioneer.getAuction(lot);
		uint256 auctionEmission = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;
		assertApproxEqAbs(auctionEmission, bp10000Emission, 10, "Auction receives correct amount of emissions (BP 10000)");

		// BP 20000
		timestamp += 1 days;
		uint256 bp17500Emission = auctioneer.exposed_getEmissionForAuction(timestamp, 1750);

		params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = timestamp;
		params[0].emissionBP = 1750;
		auctioneer.createDailyAuctions(params);
		lot = auctioneer.lotCount() - 1;

		auction = auctioneer.getAuction(lot);
		auctionEmission = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;
		assertApproxEqAbs(auctionEmission, bp17500Emission, 10, "Auction receives correct amount of emissions (BP 17500)");
	}

	function test_proofOfBid_createSingleAuction_BP10000_FutureEmissionsUnchanged() public {
		uint256 day2Timestamp = _getDayInFuture2PMTimestamp(2);
		uint256 day3Timestamp = day2Timestamp + 1 days;

		// Day 3 expected daily emission
		EpochData memory epochData = auctioneer.exposed_getEpochDataAtTimestamp(day2Timestamp);
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 10000;
		auctioneer.createDailyAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 expected daily emission
		epochData = auctioneer.exposed_getEpochDataAtTimestamp(day3Timestamp);
		uint256 day3ExpectedDailyEmission = epochData.dailyEmission;

		assertApproxEqAbs(day2ExpectedDailyEmission, day2ActualEmission, 10, "Day 2 emissions match");
		assertApproxEqAbs(
			day2ExpectedDailyEmission,
			day3ExpectedDailyEmission,
			10,
			"Day 2 and 3 daily emissions should remain unchanged if BP = 10000"
		);
	}

	function test_proofOfBid_createSingleAuction_BP20000_FutureEmissionsDecreased() public {
		uint256 day2Timestamp = _getDayInFuture2PMTimestamp(2);
		uint256 day3Timestamp = day2Timestamp + 1 days;

		// Day 3 expected daily emission
		EpochData memory epochData = auctioneer.exposed_getEpochDataAtTimestamp(day2Timestamp);
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;
		uint256 day3ExpectedDailyEmission = (epochData.emissionsRemaining - (epochData.dailyEmission * 2)) /
			(epochData.daysRemaining - 1);

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 20000;
		auctioneer.createDailyAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 actual daily emission
		epochData = auctioneer.exposed_getEpochDataAtTimestamp(day3Timestamp);
		uint256 day3ActualDailyEmission = epochData.dailyEmission;

		assertApproxEqAbs(
			day2ExpectedDailyEmission * 2,
			day2ActualEmission,
			10,
			"Day 2 emissions should be doubled (BP = 20000)"
		);
		assertGt(day2ExpectedDailyEmission, day3ExpectedDailyEmission, "Day 3 emissions should decrease if BP = 20000");
		assertApproxEqAbs(
			day3ExpectedDailyEmission,
			day3ActualDailyEmission,
			10,
			"Daily emission reduction updated correctly"
		);
	}

	function test_proofOfBid_createSingleAuction_BP5000_FutureEmissionsIncreased() public {
		uint256 day2Timestamp = _getDayInFuture2PMTimestamp(2);
		uint256 day3Timestamp = day2Timestamp + 1 days;

		// Day 3 expected daily emission
		EpochData memory epochData = auctioneer.exposed_getEpochDataAtTimestamp(day2Timestamp);
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;
		uint256 day3ExpectedDailyEmission = (epochData.emissionsRemaining - ((epochData.dailyEmission * 5000) / 10000)) /
			(epochData.daysRemaining - 1);

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 5000;
		auctioneer.createDailyAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 actual daily emission
		epochData = auctioneer.exposed_getEpochDataAtTimestamp(day3Timestamp);
		uint256 day3ActualDailyEmission = epochData.dailyEmission;

		assertApproxEqAbs(
			(day2ExpectedDailyEmission * 5000) / 10000,
			day2ActualEmission,
			10,
			"Day 2 emissions should be halved (BP = 5000)"
		);
		assertLt(day2ExpectedDailyEmission, day3ExpectedDailyEmission, "Day 3 emissions should increase if BP = 5000");
		assertApproxEqAbs(
			day3ExpectedDailyEmission,
			day3ActualDailyEmission,
			10,
			"Daily emission increase updated correctly"
		);
	}

	function test_proofOfBid_createSingleAuction_BP20000_FutureEmissionsDecreased_RevertedOnCancel() public {
		uint256 day2Timestamp = _getDayInFuture2PMTimestamp(2);
		uint256 day3Timestamp = day2Timestamp + 1 days;

		// Day 3 expected daily emission
		EpochData memory epochData = auctioneer.exposed_getEpochDataAtTimestamp(day2Timestamp);
		uint256 initialEmissionsRemaining = epochData.emissionsRemaining;
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;
		uint256 day3ExpectedDailyEmission = (epochData.emissionsRemaining - (epochData.dailyEmission * 2)) /
			(epochData.daysRemaining - 1);

		// Day 3 expected if day 2 auction cancelled
		epochData = auctioneer.exposed_getEpochDataAtTimestamp(day3Timestamp);
		uint256 day3ExpectedEmissionWithoutDay2Auction = epochData.dailyEmission;

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 20000;
		auctioneer.createDailyAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 actual daily emission
		epochData = auctioneer.exposed_getEpochDataAtTimestamp(day3Timestamp);
		uint256 day3ActualDailyEmission = epochData.dailyEmission;

		assertApproxEqAbs(
			day2ExpectedDailyEmission * 2,
			day2ActualEmission,
			10,
			"Day 2 emissions should be doubled (BP = 20000)"
		);
		assertGt(day2ExpectedDailyEmission, day3ExpectedDailyEmission, "Day 3 emissions should decrease if BP = 20000");
		assertApproxEqAbs(
			day3ExpectedDailyEmission,
			day3ActualDailyEmission,
			10,
			"Daily emission reduction updated correctly"
		);

		// Cancel auction
		auctioneer.cancelAuction(lot, false);

		// Day 3 should return to initial conditions
		epochData = auctioneer.exposed_getEpochDataAtTimestamp(day3Timestamp);
		assertApproxEqAbs(
			initialEmissionsRemaining,
			epochData.emissionsRemaining,
			10,
			"Emissions remaining should return to initial"
		);
		assertApproxEqAbs(
			day3ExpectedEmissionWithoutDay2Auction,
			epochData.dailyEmission,
			10,
			"Day 2 and 3 emissions should return to matching"
		);
	}

	uint256 public user1Bids = 1100;
	uint256 public user2Bids = 580;
	uint256 public user3Bids = 1520;
	uint256 public user4Bids = 960;
	uint256 public totalBids = user1Bids + user2Bids + user3Bids + user4Bids;

	function _setUpFarmBids(uint256 lot) internal {
		// Set farm
		auctioneer.setFarm(address(farm));

		vm.warp(auctioneer.getAuction(lot).unlockTimestamp);
		_multibidLot(user2, user2Bids, lot);
		_multibidLot(user3, user3Bids, lot);
		_multibidLot(user4, user4Bids, lot);
		_multibidLot(user1, user1Bids, lot);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(lot).bidData.nextBidBy + 1);
	}

	function _getUsersExpectedEmissions(
		uint256 lot
	)
		internal
		view
		returns (
			uint256 user1ExpectedEmissions,
			uint256 user2ExpectedEmissions,
			uint256 user3ExpectedEmissions,
			uint256 user4ExpectedEmissions
		)
	{
		uint256 emissions = auctioneer.getAuction(lot).emissions.biddersEmission;
		user1ExpectedEmissions = (emissions * user1Bids) / totalBids;
		user2ExpectedEmissions = (emissions * user2Bids) / totalBids;
		user3ExpectedEmissions = (emissions * user3Bids) / totalBids;
		user4ExpectedEmissions = (emissions * user4Bids) / totalBids;
	}

	function test_proofOfBid_claimAuctionEmissions_ExpectEmit_UserClaimedLotEmissions() public {
		_setUpFarmBids(0);

		(uint256 user1ExpectedEmissions, , , ) = _getUsersExpectedEmissions(0);

		vm.expectEmit(true, true, true, true);
		emit UserClaimedLotEmissions(
			0,
			user1,
			user1ExpectedEmissions / 2,
			user1ExpectedEmissions - (user1ExpectedEmissions / 2)
		);

		vm.prank(user1);
		uint256[] memory auctionsToClaim = new uint256[](1);
		auctionsToClaim[0] = 0;
		auctioneer.claimAuctionEmissions(auctionsToClaim);
	}

	function test_proofOfBid_claimAuctionEmissions_MultipleAuctions() public {
		// Create day 1 auction
		_createBaseAuctionOnDay(2);
		_createBaseAuctionOnDay(3);

		_setUpFarmBids(0);
		_setUpFarmBids(1);
		_setUpFarmBids(2);

		(uint256 user1Lot0ExpectedEmissions, , , ) = _getUsersExpectedEmissions(0);
		(uint256 user1Lot1ExpectedEmissions, , , ) = _getUsersExpectedEmissions(1);
		(uint256 user1Lot2ExpectedEmissions, , , ) = _getUsersExpectedEmissions(2);

		vm.expectEmit(true, true, true, true);
		emit UserClaimedLotEmissions(
			0,
			user1,
			user1Lot0ExpectedEmissions / 2,
			user1Lot0ExpectedEmissions - (user1Lot0ExpectedEmissions / 2)
		);
		vm.expectEmit(true, true, true, true);
		emit UserClaimedLotEmissions(
			1,
			user1,
			user1Lot1ExpectedEmissions / 2,
			user1Lot1ExpectedEmissions - (user1Lot1ExpectedEmissions / 2)
		);
		vm.expectEmit(true, true, true, true);
		emit UserClaimedLotEmissions(
			2,
			user1,
			user1Lot2ExpectedEmissions / 2,
			user1Lot2ExpectedEmissions - (user1Lot2ExpectedEmissions / 2)
		);

		vm.prank(user1);
		uint256[] memory auctionsToClaim = new uint256[](3);
		auctionsToClaim[0] = 0;
		auctionsToClaim[1] = 1;
		auctionsToClaim[2] = 2;
		auctioneer.claimAuctionEmissions(auctionsToClaim);
	}

	function test_proofOfBid_firstBidAddsAuctionToUserClaimableLots() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		uint256[] memory lots = auctioneer.getUserClaimableLots(user1);
		assertEq(lots.length, 0, "Claimable lots should be []");

		_bid(user1);

		lots = auctioneer.getUserClaimableLots(user1);
		assertEq(lots.length, 1, "Claimable lots should be [0]");
		assertEq(lots[0], 0, "First claimable lots should be 0");
	}

	function test_proofOfBid_claimAuctionEmissions_RevertWhen_AuctionNotEnded() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.expectRevert(AuctionStillRunning.selector);

		// Claim
		uint256[] memory auctionsToClaim = new uint256[](1);
		auctionsToClaim[0] = 0;
		vm.prank(user1);
		auctioneer.claimAuctionEmissions(auctionsToClaim);
	}

	function test_proofOfBid_claimAuctionEmissions_MarkedAsClaimed() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		bool claimed = auctioneer.getAuctionUser(0, user1).claimed;
		assertEq(claimed, false, "User has not claimed emissions");

		uint256[] memory auctionsToClaim = new uint256[](1);
		auctionsToClaim[0] = 0;
		vm.prank(user1);
		auctioneer.claimAuctionEmissions(auctionsToClaim);

		claimed = auctioneer.getAuctionUser(0, user1).claimed;
		assertEq(claimed, true, "User has claimed emissions");
	}

	function test_proofOfBid_claimAuctionEmissions_AfterClaim_LotRemovedFromList() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		ClaimableLotData[] memory lotDatas = auctioneer.getUserClaimableLotsData(user1);
		uint256[] memory claimableLots = auctioneer.getUserClaimableLots(user1);
		assertGt(lotDatas.length, 0, "User has lotDatas to claim");
		assertGt(claimableLots.length, 0, "User has lots to claim");

		// Claim
		uint256[] memory auctionsToClaim = new uint256[](1);
		auctionsToClaim[0] = 0;
		vm.prank(user1);
		auctioneer.claimAuctionEmissions(auctionsToClaim);

		lotDatas = auctioneer.getUserClaimableLotsData(user1);
		claimableLots = auctioneer.getUserClaimableLots(user1);
		assertEq(lotDatas.length, 0, "LotData removed from lotData list");
		assertEq(claimableLots.length, 0, "Lot removed from claimableLots list");
	}

	function test_proofOfBid_claimAuctionEmissions_EarlyHarvest_50PercTax() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		ClaimableLotData[] memory lotDatas = auctioneer.getUserClaimableLotsData(user1);
		assertGt(lotDatas[0].timeUntilMature, 0, "Emissions immature, incurs tax");

		vm.warp(block.timestamp + 1 days);

		// Initial status
		uint256 userGOInit = GO.balanceOf(user1);
		uint256 deadGOInit = GO.balanceOf(dead);

		uint256[] memory auctionsToClaim = new uint256[](1);
		auctionsToClaim[0] = 0;
		vm.prank(user1);
		auctioneer.claimAuctionEmissions(auctionsToClaim);

		// Final status
		uint256 userGOFinal = GO.balanceOf(user1);
		uint256 deadGOFinal = GO.balanceOf(dead);

		// Checks
		assertEq(userGOFinal - userGOInit, lotDatas[0].emissions / 2, "User receives taxed emissions");
		assertEq(deadGOFinal - deadGOInit, lotDatas[0].emissions - (lotDatas[0].emissions / 2), "Emission taxes burned");
	}

	function test_proofOfBid_claimAuctionEmissions_DelayedHarvest_0PercTax() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		ClaimableLotData[] memory lotDatas = auctioneer.getUserClaimableLotsData(user1);
		assertGt(lotDatas[0].timeUntilMature, 0, "Emissions immature, incurs tax");

		// Warp to mature time
		vm.warp(block.timestamp + lotDatas[0].timeUntilMature);
		lotDatas = auctioneer.getUserClaimableLotsData(user1);
		assertEq(lotDatas[0].timeUntilMature, 0, "Emissions mature, no tax");

		// Initial status
		uint256 userGOInit = GO.balanceOf(user1);
		uint256 deadGOInit = GO.balanceOf(dead);

		uint256[] memory auctionsToClaim = new uint256[](1);
		auctionsToClaim[0] = 0;
		vm.prank(user1);
		auctioneer.claimAuctionEmissions(auctionsToClaim);

		// Final status
		uint256 userGOFinal = GO.balanceOf(user1);
		uint256 deadGOFinal = GO.balanceOf(dead);

		// Checks
		assertEq(userGOFinal - userGOInit, lotDatas[0].emissions, "User receives full emissions");
		assertEq(deadGOFinal - deadGOInit, 0, "Emission not taxed");
	}
}
