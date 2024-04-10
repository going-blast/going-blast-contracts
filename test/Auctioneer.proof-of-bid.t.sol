// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBMath, AuctionViewUtils } from "../src/AuctionUtils.sol";

contract AuctioneerProofOfBidTest is AuctioneerHelper {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

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

	function test_proofOfBid_createSingleAuction_EmissionScalesWithBP() public {
		uint256 timestamp = _getDayInFuture2PMTimestamp(3);
		EpochData memory epochData = auctioneerEmissions.getEpochDataAtTimestamp(timestamp);

		uint256 bp10000Emission = auctioneerEmissions.getAuctionEmission(timestamp, 10000);
		assertEq(
			bp10000Emission,
			epochData.emissionsRemaining / epochData.daysRemaining,
			"Should give share of remaining emissions"
		);

		uint256 bp20000Emission = auctioneerEmissions.getAuctionEmission(timestamp, 20000);
		assertEq(
			bp20000Emission,
			2 * (epochData.emissionsRemaining / epochData.daysRemaining),
			"Should give double share of remaining emissions"
		);

		assertEq(bp10000Emission * 2, bp20000Emission, "Doubling bp should double emissions");

		uint256 bp0Emission = auctioneerEmissions.getAuctionEmission(timestamp, 0);
		assertEq(bp0Emission, 0, "0 BP should give 0 emissions");
	}
	function test_proofOfBid_createSingleAuction_EmissionsMatchExpected() public {
		uint256 timestamp = _getDayInFuture2PMTimestamp(3);

		// BP 10000
		uint256 bp10000Emission = auctioneerEmissions.getAuctionEmission(timestamp, 10000);

		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = timestamp;
		params[0].emissionBP = 10000;
		auctioneer.createAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;

		Auction memory auction = auctioneer.getAuction(lot);
		uint256 auctionEmission = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;
		assertApproxEqAbs(auctionEmission, bp10000Emission, 10, "Auction receives correct amount of emissions (BP 10000)");

		// BP 20000
		timestamp += 1 days;
		uint256 bp17500Emission = auctioneerEmissions.getAuctionEmission(timestamp, 1750);

		params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = timestamp;
		params[0].emissionBP = 1750;
		auctioneer.createAuctions(params);
		lot = auctioneer.lotCount() - 1;

		auction = auctioneer.getAuction(lot);
		auctionEmission = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;
		assertApproxEqAbs(auctionEmission, bp17500Emission, 10, "Auction receives correct amount of emissions (BP 17500)");
	}

	function test_proofOfBid_createSingleAuction_BP10000_FutureEmissionsUnchanged() public {
		uint256 day2Timestamp = _getDayInFuture2PMTimestamp(2);
		uint256 day3Timestamp = day2Timestamp + 1 days;

		// Day 3 expected daily emission
		EpochData memory epochData = auctioneerEmissions.getEpochDataAtTimestamp(day2Timestamp);
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 10000;
		auctioneer.createAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 expected daily emission
		epochData = auctioneerEmissions.getEpochDataAtTimestamp(day3Timestamp);
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
		EpochData memory epochData = auctioneerEmissions.getEpochDataAtTimestamp(day2Timestamp);
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;
		uint256 day3ExpectedDailyEmission = (epochData.emissionsRemaining - (epochData.dailyEmission * 2)) /
			(epochData.daysRemaining - 1);

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 20000;
		auctioneer.createAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 actual daily emission
		epochData = auctioneerEmissions.getEpochDataAtTimestamp(day3Timestamp);
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
		EpochData memory epochData = auctioneerEmissions.getEpochDataAtTimestamp(day2Timestamp);
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;
		uint256 day3ExpectedDailyEmission = (epochData.emissionsRemaining - epochData.dailyEmission.scaleByBP(5000)) /
			(epochData.daysRemaining - 1);

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 5000;
		auctioneer.createAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 actual daily emission
		epochData = auctioneerEmissions.getEpochDataAtTimestamp(day3Timestamp);
		uint256 day3ActualDailyEmission = epochData.dailyEmission;

		assertApproxEqAbs(
			day2ExpectedDailyEmission.scaleByBP(5000),
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
		EpochData memory epochData = auctioneerEmissions.getEpochDataAtTimestamp(day2Timestamp);
		uint256 initialEmissionsRemaining = epochData.emissionsRemaining;
		uint256 day2ExpectedDailyEmission = epochData.dailyEmission;
		uint256 day3ExpectedDailyEmission = (epochData.emissionsRemaining - (epochData.dailyEmission * 2)) /
			(epochData.daysRemaining - 1);

		// Day 3 expected if day 2 auction cancelled
		epochData = auctioneerEmissions.getEpochDataAtTimestamp(day3Timestamp);
		uint256 day3ExpectedEmissionWithoutDay2Auction = epochData.dailyEmission;

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = day2Timestamp;
		params[0].emissionBP = 20000;
		auctioneer.createAuctions(params);
		uint256 lot = auctioneer.lotCount() - 1;
		uint256 day2ActualEmission = auctioneer.getAuction(lot).emissions.biddersEmission +
			auctioneer.getAuction(lot).emissions.treasuryEmission;

		// Day 3 actual daily emission
		epochData = auctioneerEmissions.getEpochDataAtTimestamp(day3Timestamp);
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
		epochData = auctioneerEmissions.getEpochDataAtTimestamp(day3Timestamp);
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
		vm.warp(auctioneer.getAuction(lot).unlockTimestamp);
		_multibidLot(user2, user2Bids, lot);
		_multibidLot(user3, user3Bids, lot);
		_multibidLot(user4, user4Bids, lot);
		_multibidLot(user1, user1Bids, lot);

		// Harvestable after next bid by
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

	function test_proofOfBid_harvestAuctionEmissions_ExpectEmit_UserHarvestedLotEmissions() public {
		_setUpFarmBids(0);

		(uint256 user1ExpectedEmissions, , , ) = _getUsersExpectedEmissions(0);

		vm.expectEmit(true, true, true, true);
		emit UserHarvestedLotEmissions(
			0,
			user1,
			user1ExpectedEmissions / 2,
			user1ExpectedEmissions - (user1ExpectedEmissions / 2)
		);

		vm.prank(user1);
		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);
	}

	function test_proofOfBid_harvestAuctionEmissions_MultipleAuctions() public {
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
		emit UserHarvestedLotEmissions(
			0,
			user1,
			user1Lot0ExpectedEmissions / 2,
			user1Lot0ExpectedEmissions - (user1Lot0ExpectedEmissions / 2)
		);
		vm.expectEmit(true, true, true, true);
		emit UserHarvestedLotEmissions(
			1,
			user1,
			user1Lot1ExpectedEmissions / 2,
			user1Lot1ExpectedEmissions - (user1Lot1ExpectedEmissions / 2)
		);
		vm.expectEmit(true, true, true, true);
		emit UserHarvestedLotEmissions(
			2,
			user1,
			user1Lot2ExpectedEmissions / 2,
			user1Lot2ExpectedEmissions - (user1Lot2ExpectedEmissions / 2)
		);

		vm.prank(user1);
		uint256[] memory auctionsToHarvest = new uint256[](3);
		auctionsToHarvest[0] = 0;
		auctionsToHarvest[1] = 1;
		auctionsToHarvest[2] = 2;
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);
	}

	function test_proofOfBid_firstBidAddsAuctionToUserInteractedLots() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		uint256[] memory unharvestedLots = auctioneerUser.getUserUnharvestedLots(user1);
		assertEq(unharvestedLots.length, 0, "unharvestedLots lots should be []");

		_bid(user1);

		unharvestedLots = auctioneerUser.getUserUnharvestedLots(user1);
		assertEq(unharvestedLots.length, 1, "unharvestedLots should be [0]");
		assertEq(unharvestedLots[0], 0, "First unharvestedLot should be 0");
	}

	function test_proofOfBid_harvestAuctionEmissions_RevertWhen_AuctionNotEnded() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.expectRevert(AuctionStillRunning.selector);

		// Harvest
		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);
	}

	function test_proofOfBid_harvestAuctionEmissions_MarkedAsHarvested() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		bool harvested = auctioneerUser.getAuctionUser(0, user1).emissionsHarvested;
		assertEq(harvested, false, "User has not harvested emissions");

		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);

		harvested = auctioneerUser.getAuctionUser(0, user1).emissionsHarvested;
		assertEq(harvested, true, "User has harvested emissions");
	}

	function test_proofOfBid_harvestAuctionEmissions_AfterClaim_LotRemovedFromList() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		uint256[] memory interactedLots = auctioneerUser.getUserInteractedLots(user1);
		uint256[] memory unharvestedLots = auctioneerUser.getUserUnharvestedLots(user1);
		assertEq(interactedLots.length, 0, "User has not interacted with any lots");
		assertEq(unharvestedLots.length, 0, "User has no unharvested lots");

		_bid(user1);

		vm.warp(block.timestamp + 1 days);

		interactedLots = auctioneerUser.getUserInteractedLots(user1);
		unharvestedLots = auctioneerUser.getUserUnharvestedLots(user1);
		assertEq(interactedLots.length, 1, "User has interacted with one lot");
		assertEq(interactedLots[0], 0, "Users first interacted lot is lot 0");
		assertEq(unharvestedLots.length, 1, "User has one unharvested lots");
		assertEq(unharvestedLots[0], 0, "Users unharvested lot is lot 0");

		// Claim
		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);

		interactedLots = auctioneerUser.getUserInteractedLots(user1);
		unharvestedLots = auctioneerUser.getUserUnharvestedLots(user1);
		assertEq(interactedLots.length, 1, "User has still interacted with one lot");
		assertEq(interactedLots[0], 0, "Users first interacted lot is still lot 0");
		assertEq(unharvestedLots.length, 0, "Lot removed from unharvestedLots list");
	}

	function test_proofOfBid_harvestAuctionEmissions_EarlyHarvest_50PercTax() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		UserLotInfo memory user1LotInfo = auctioneerUser.getUserLotInfo(0, user1);
		assertGt(user1LotInfo.timeUntilMature, 0, "Emissions immature, incurs tax");

		vm.warp(block.timestamp + 1 days);

		// Initial status
		uint256 userGOInit = GO.balanceOf(user1);
		uint256 deadGOInit = GO.balanceOf(dead);

		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);

		// Final status
		uint256 userGOFinal = GO.balanceOf(user1);
		uint256 deadGOFinal = GO.balanceOf(dead);

		// Checks
		assertEq(userGOFinal - userGOInit, user1LotInfo.emissionsEarned / 2, "User receives taxed emissions");
		assertEq(
			deadGOFinal - deadGOInit,
			user1LotInfo.emissionsEarned - (user1LotInfo.emissionsEarned / 2),
			"Emission taxes burned"
		);
	}

	function test_proofOfBid_harvestAuctionEmissions_DelayedHarvest_0PercTax() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		_bid(user1);

		UserLotInfo memory user1LotInfo = auctioneerUser.getUserLotInfo(0, user1);
		assertGt(user1LotInfo.timeUntilMature, 0, "Emissions immature, incurs tax");

		// Warp to mature time
		vm.warp(block.timestamp + user1LotInfo.timeUntilMature);
		user1LotInfo = auctioneerUser.getUserLotInfo(0, user1);
		assertEq(user1LotInfo.timeUntilMature, 0, "Emissions mature, no tax");

		// Initial status
		uint256 userGOInit = GO.balanceOf(user1);
		uint256 deadGOInit = GO.balanceOf(dead);

		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = 0;
		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);

		// Final status
		uint256 userGOFinal = GO.balanceOf(user1);
		uint256 deadGOFinal = GO.balanceOf(dead);

		// Checks
		assertEq(userGOFinal - userGOInit, user1LotInfo.emissionsEarned, "User receives full emissions");
		assertEq(deadGOFinal - deadGOInit, 0, "Emission not taxed");

		// LotEmissionInfo checks
		user1LotInfo = auctioneerUser.getUserLotInfo(0, user1);
		assertEq(user1LotInfo.emissionsHarvested, true, "Emissions are marked as harvested in lotEmissionInfo");
	}

	function test_proofOfBid_auctionWithRunes_harvestAuctionEmissions_EarlyHarvest_50PercTax() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_multibidWithRune(user1, lot, 86, 1);
		_multibidWithRune(user2, lot, 91, 2);
		_multibidWithRune(user3, lot, 32, 1);
		_multibidWithRune(user4, lot, 77, 2);

		uint256 auctionEmissions = auctioneer.getAuction(lot).emissions.biddersEmission;

		vm.warp(block.timestamp + 1 days);

		// Initial status
		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = lot;

		// USER 1
		BidCounts memory user1BidCounts = auctioneerUser.getUserLotInfo(lot, user1).bidCounts;
		uint256 user1EmissionsTotal = (auctionEmissions * user1BidCounts.user) / user1BidCounts.auction;
		uint256 user1Harvestable = user1EmissionsTotal / 2;
		uint256 user1Burnable = user1EmissionsTotal - user1Harvestable;
		_expectTokenTransfer(GO, address(auctioneerEmissions), user1, user1Harvestable);
		_expectTokenTransfer(GO, address(auctioneerEmissions), dead, user1Burnable);

		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);

		// USER 2
		BidCounts memory user2BidCounts = auctioneerUser.getUserLotInfo(lot, user2).bidCounts;
		uint256 user2EmissionsTotal = (auctionEmissions * user2BidCounts.user) / user2BidCounts.auction;
		uint256 user2Harvestable = user2EmissionsTotal / 2;
		uint256 user2Burnable = user2EmissionsTotal - user2Harvestable;
		_expectTokenTransfer(GO, address(auctioneerEmissions), user2, user2Harvestable);
		_expectTokenTransfer(GO, address(auctioneerEmissions), dead, user2Burnable);

		vm.prank(user2);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);
	}

	function test_proofOfBid_auctionWithRunes_harvestAuctionEmissions_MatureHarvest_0PercTax() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		_multibidWithRune(user1, lot, 36, 1);
		_multibidWithRune(user2, lot, 1, 2);
		_multibidWithRune(user3, lot, 32, 1);
		_multibidWithRune(user4, lot, 77, 2);

		uint256 auctionEmissions = auctioneer.getAuction(lot).emissions.biddersEmission;

		vm.warp(block.timestamp + 1 days);
		vm.warp(block.timestamp + auctioneerUser.getUserLotInfo(0, user1).timeUntilMature);

		// Initial status
		uint256[] memory auctionsToHarvest = new uint256[](1);
		auctionsToHarvest[0] = lot;

		// USER 1
		BidCounts memory user1BidCounts = auctioneerUser.getUserLotInfo(lot, user1).bidCounts;
		_expectTokenTransfer(
			GO,
			address(auctioneerEmissions),
			user1,
			(auctionEmissions * user1BidCounts.user) / (user1BidCounts.auction)
		);

		vm.prank(user1);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);

		// USER 2
		BidCounts memory user2BidCounts = auctioneerUser.getUserLotInfo(lot, user2).bidCounts;
		_expectTokenTransfer(
			GO,
			address(auctioneerEmissions),
			user2,
			(auctionEmissions * user2BidCounts.user) / (user2BidCounts.auction)
		);

		vm.prank(user2);
		auctioneer.harvestAuctionsEmissions(auctionsToHarvest, false);
	}
}
