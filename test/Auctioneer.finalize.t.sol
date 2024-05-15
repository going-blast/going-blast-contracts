// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils, GBMath } from "../src/AuctionUtils.sol";

contract AuctioneerFinalizeTest is AuctioneerHelper {
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
		_giveTreasuryXXandYYandApprove();

		AuctionParams[] memory params = new AuctionParams[](2);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		// Create multi token auction
		params[1] = _getMultiTokenSingleAuctionParams();

		// Create single token + nfts auction
		auctioneer.createAuctions(params);
	}

	function test_winning_finalizeAuction_RevertWhen_AuctionStillRunning() public {
		vm.expectRevert(AuctionStillRunning.selector);
		auctioneer.finalizeAuction(0);
	}

	function test_winning_finalizeAuction_NotRevertWhen_AuctionAlreadyFinalized() public {
		_warpToUnlockTimestamp(0);
		_bid(user1);
		_warpToAuctionEndTimestamp(0);

		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);
		auctioneer.finalizeAuction(0);

		auctioneer.finalizeAuction(0);
	}

	function test_finalize_finalizeAuction_ExpectEmit_AuctionFinalized() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);

		vm.prank(user1);
		auctioneer.finalizeAuction(0);
	}

	function test_finalize_finalizeAuction_ExpectState_AuctionMarkedAsFinalized() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		auctioneer.finalizeAuction(0);

		assertEq(auctioneerAuction.getAuction(0).finalized, true, "Auction marked finalized");
	}

	function test_finalize_claimLot_ExpectEmit_AuctionFinalized() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);
		vm.deal(user1, 1e18);

		uint256 price = auctioneerAuction.getAuction(0).bidData.bid;

		// Not claimable up until end of auction
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimLot{ value: price }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);

		vm.prank(user1);
		auctioneer.claimLot{ value: price }(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
	}

	function testFail_finalize_claimLot_alreadyFinalized_NotExpectEmit_AuctionFinalized() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

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
		auctioneer.claimLot(0, ClaimLotOptions({ paymentType: PaymentType.WALLET }));
	}

	function test_finalizeAuction_TransferEmissionsToTreasury() public {
		_warpToUnlockTimestamp(0);
		_bid(user1);
		_warpToAuctionEndTimestamp(0);

		Auction memory auction = auctioneerAuction.getAuction(0);

		_expectTokenTransfer(GO, address(auctioneerEmissions), treasury, auction.emissions.treasuryEmission);

		auctioneer.finalizeAuction(0);
	}

	function test_finalizeAuction_NoBids_CancelFallback() public {
		_warpToAuctionEndTimestamp(0);

		Auction memory auction = auctioneerAuction.getAuction(0);

		uint256 treasuryGOInit = GO.balanceOf(treasury);
		uint256 treasuryETH = treasury.balance;
		uint256 auctionTotalEmission = auction.emissions.biddersEmission + auction.emissions.treasuryEmission;
		uint256 epoch0EmissionsRemaining = auctioneerEmissions.epochEmissionsRemaining(0);

		uint256 auctionsOnDay = auctioneerAuction.getAuctionsPerDay(auction.day);
		uint256 bpOnDay = auctioneerAuction.dailyCumulativeEmissionBP(auction.day);

		vm.expectEmit(true, true, true, true);
		emit AuctionCancelled(0);

		auctioneer.finalizeAuction(0);

		assertEq(GO.balanceOf(treasury), treasuryGOInit, "Treasury receives GO emissions from auction");
		assertEq(treasury.balance, treasuryETH + auction.rewards.tokens[0].amount, "Lot ETH returned to treasury");
		assertEq(
			auctioneerEmissions.epochEmissionsRemaining(0),
			epoch0EmissionsRemaining + auctionTotalEmission,
			"Emissions returned to epoch"
		);
		assertEq(auctioneerAuction.getAuctionsPerDay(auction.day), auctionsOnDay - 1, "Auctions per day decremented");
		assertEq(
			auctioneerAuction.dailyCumulativeEmissionBP(auction.day),
			bpOnDay - auction.emissions.bp,
			"BP per day reduced by auction bp"
		);
		assertEq(auctioneerAuction.getAuction(0).finalized, true, "Auction should be marked as finalized");
	}

	function test_finalizeAuction_Should_DistributeLotRevenue_RevenueLessThanLotValue() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		uint256 revenue = auctioneerAuction.getAuction(0).bidData.revenue;
		uint256 lotValue = auctioneerAuction.getAuction(0).rewards.estimatedValue;
		assertLt(revenue, lotValue, "Validate revenue < lotValue");

		_prepExpectETHBalChange(0, treasury);
		_prepExpectETHBalChange(0, address(farm));
		_prepExpectETHBalChange(0, address(auctioneer));

		// Finalize
		auctioneer.finalizeAuction(0);

		// Treasury should receive full lot value
		_expectETHBalChange(0, treasury, int256(revenue), "Treasury");
		_expectETHBalChange(0, address(auctioneer), -1 * int256(revenue), "Auctioneer");

		// Farm should receive nothing
		_expectETHBalChange(0, address(farm), 0, "Farm");
	}

	function test_finalizeAuction_Should_DistributeLotRevenue_RevenueLessThan110PercLotValue() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		// 2857 bids to hit 1 ETH
		_multibid(user2, 480);
		_multibid(user3, 1520);
		_multibid(user4, 960);
		_multibid(user1, 100);

		// Claimable after next bid by
		Auction memory auction = auctioneerAuction.getAuction(0);
		vm.warp(auction.bidData.nextBidBy + 1);

		uint256 revenue = auction.bidData.revenue;
		uint256 lotValue = auction.rewards.estimatedValue;
		assertGt(revenue, lotValue, "Validate revenue > lotValue");
		assertLt(revenue, (lotValue * 110) / 100, "Validate revenue < 110% lotValue");

		_prepExpectETHBalChange(0, treasury);
		_prepExpectETHBalChange(0, address(farm));
		_prepExpectETHBalChange(0, address(auctioneer));

		// Claim
		auctioneer.finalizeAuction(0);

		// Treasury should receive full lot value
		_expectETHBalChange(0, treasury, int256(revenue), "Treasury");
		_expectETHBalChange(0, address(auctioneer), -1 * int256(revenue), "Auctioneer");

		// Farm should receive nothing
		_expectETHBalChange(0, address(farm), 0, "Farm");
	}

	function _farmDeposit() public {
		vm.prank(treasury);
		GO.transfer(user1, 10e18);
		vm.prank(user1);
		GO.approve(address(farm), 10e18);
		vm.prank(user1);
		farm.deposit(goPid, 10e18, user1);
	}

	function test_finalizeAuction_Should_DistributeLotRevenue_RevenueGreaterThanLotValue() public {
		// Deposit some non zero value into farm to prevent distribution fallback
		_farmDeposit();

		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 1580);
		_multibid(user3, 1520);
		_multibid(user4, 1960);
		_multibid(user1, 1100);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		uint256 revenue = auctioneerAuction.getAuction(0).bidData.revenue;
		uint256 lotValue = auctioneerAuction.getAuction(0).rewards.estimatedValue;
		uint256 lotValue110Perc = lotValue.scaleByBP(11000);
		assertGt(revenue, lotValue110Perc, "Validate revenue > 110% lotValue");

		uint256 treasurySplit = auctioneerAuction.treasurySplit();
		uint256 profit = revenue - lotValue110Perc;
		uint256 treasuryExpectedDisbursement = lotValue110Perc + profit.scaleByBP(treasurySplit);
		uint256 farmExpectedDisbursement = profit.scaleByBP(10000 - treasurySplit);

		_prepExpectETHBalChange(0, treasury);
		_prepExpectETHBalChange(0, address(farm));
		_prepExpectETHBalChange(0, address(auctioneer));

		// Claim
		auctioneer.finalizeAuction(0);

		_expectETHBalChange(0, treasury, int256(treasuryExpectedDisbursement), "Treasury");
		_expectETHBalChange(0, address(farm), int256(farmExpectedDisbursement), "Farm");
		_expectETHBalChange(0, address(auctioneer), -1 * int256(revenue), "Auctioneer");
	}
}
