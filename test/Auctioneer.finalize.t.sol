// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils, GBMath } from "../src/AuctionUtils.sol";

contract AuctioneerFinalizeTest is AuctioneerHelper {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	function setUp() public override {
		super.setUp();

		_setupAuctioneerTreasury();
		_setupAuctioneerCreator();
		_giveUsersTokensAndApprove();
		_giveCreatorXXandYYandApprove();

		// Create single token auction
		AuctionParams memory singleTokenParams = _getBaseAuctionParams();
		// Create multi token auction
		AuctionParams memory multiTokenParams = _getMultiTokenSingleAuctionParams();

		// Create single token + nfts auction
		_createAuction(singleTokenParams);
		_createAuction(multiTokenParams);
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
		auctioneer.claimLot(0, "");

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
		auctioneer.claimLot{ value: price }(0, "");

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);

		vm.prank(user1);
		auctioneer.claimLot{ value: price }(0, "");
	}

	function testFail_finalize_claimLot_alreadyFinalized_NotExpectEmit_AuctionFinalized() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimLot(0, "");

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
		auctioneer.claimLot(0, "");
	}

	function test_finalizeAuction_NoBids_CancelFallback() public {
		_warpToAuctionEndTimestamp(0);

		Auction memory auction = auctioneerAuction.getAuction(0);

		uint256 creatorETH = creator.balance;

		vm.expectEmit(true, true, true, true);
		emit AuctionCancelled(creator, 0);

		auctioneer.finalizeAuction(0);

		assertEq(creator.balance, creatorETH + auction.rewards.tokens[0].amount, "Lot ETH returned to creator");
		assertEq(auctioneerAuction.getAuction(0).finalized, true, "Auction should be marked as finalized");
	}

	function test_finalizeAuction_Should_DistributeLotRevenue() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		uint256 revenue = auctioneerAuction.getAuction(0).bidData.revenue;
		uint256 treasuryCut = revenue.scaleByBP(auctioneer.treasuryCut());
		uint256 creatorCut = revenue - treasuryCut;

		_prepExpectETHBalChange(0, creator);
		_prepExpectETHBalChange(0, treasury);
		_prepExpectETHBalChange(0, address(auctioneer));

		// Finalize
		auctioneer.finalizeAuction(0);

		// Creator should receive cut
		_expectETHBalChange(0, address(creator), int256(creatorCut), "Creator");

		// Treasury should receive cut
		_expectETHBalChange(0, address(treasury), int256(treasuryCut), "Treasury");

		// Should be removed from auctioneer
		_expectETHBalChange(0, address(auctioneer), -1 * int256(revenue), "Auctioneer");
	}
}
