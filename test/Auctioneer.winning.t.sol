// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBMath, AuctionViewUtils } from "../src/AuctionUtils.sol";

contract AuctioneerWinningTest is AuctioneerHelper {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	function setUp() public override {
		super.setUp();

		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_giveTreasuryXXandYYandApprove();

		// Create single token auction
		AuctionParams memory singleTokenParams = _getBaseAuctionParams();
		// Create multi token auction
		AuctionParams memory multiTokenParams = _getMultiTokenSingleAuctionParams();

		// Create single token + nfts auction
		auctioneer.createAuction(singleTokenParams);
		auctioneer.createAuction(multiTokenParams);
	}

	function test_winning_claimLot_RevertWhen_AuctionStillRunning() public {
		vm.expectRevert(AuctionStillRunning.selector);
		auctioneer.claimLot(0, "");
	}

	function test_winning_claimLot_ExpectEmit_ClaimedLot() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Not claimable up until end of auction
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy);

		// Price
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		vm.deal(user1, lotPrice);

		vm.expectRevert(AuctionStillRunning.selector);
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "");

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		_expectEmitAuctionEvent_Claim(0, user1, "");

		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "");
	}

	function test_winning_claimLot_ExpectEmit_ClaimedLot_WithMessage() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		vm.deal(user1, lotPrice);
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		_expectEmitAuctionEvent_Claim(0, user1, "CLAIM CLAIM CLAIM");

		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "CLAIM CLAIM CLAIM");
	}

	function test_winning_claimLotWinnings_RevertWhen_NotWinner() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);
		assertEq(auctioneerAuction.getAuction(0).bidData.bidUser, user1, "User1 won auction");

		// User2 claim reverted
		vm.expectRevert(NotWinner.selector);
		vm.prank(user2);
		auctioneer.claimLot(0, "");
	}

	function test_winning_claimLotWinnings_RevertWhen_UserAlreadyClaimedLot() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Price
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		vm.deal(user1, lotPrice);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Claim once
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "");
		assertEq(auctioneer.getAuctionUser(0, user1).lotClaimed, true, "AuctionUser marked as lotClaimed");

		// Revert on claim again
		vm.expectRevert(UserAlreadyClaimedLot.selector);
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "");
	}

	function test_winning_winnerCanPayForLotFromWallet() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		uint256 lotPrize = 1e18;
		vm.deal(user1, lotPrice);

		_prepExpectETHBalChange(0, user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "");

		_expectETHBalChange(
			0,
			user1,
			(int256(lotPrice) * -1) + int256(lotPrize),
			"User1. ETH decrease by lot price, increase by prize"
		);
	}

	function test_winning_auctionIsMarkedAsClaimed() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);

		// Give ETH to pay
		vm.deal(user1, 1e18);
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "");
		assertEq(auctioneer.getAuctionUser(0, user1).lotClaimed, true, "AuctionUser marked as lotClaimed");
	}

	function test_winning_userReceivesLotTokens() public {
		vm.warp(auctioneerAuction.getAuction(1).unlockTimestamp);
		_bidOnLot(user1, 1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(1).bidData.nextBidBy + 1);

		// Give ETH to pay
		vm.deal(user1, 1e18);
		uint256 lotPrice = auctioneerAuction.getAuction(1).bidData.bid;
		uint256 lotPrize = 1e18;

		// Tokens init
		_prepExpectETHBalChange(0, user1);
		uint256 userXXInit = XXToken.balanceOf(user1);
		uint256 userYYInit = YYToken.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(1, "");

		// User received lot
		Auction memory auction = auctioneerAuction.getAuction(1);
		_expectETHBalChange(
			0,
			user1,
			(-1 * int256(lotPrice)) + int256(lotPrize),
			"User1. ETH decrease by price, increase by prize"
		);
		assertEq(XXToken.balanceOf(user1) - userXXInit, auction.rewards.tokens[1].amount, "User received XX from lot");
		assertEq(YYToken.balanceOf(user1) - userYYInit, auction.rewards.tokens[2].amount, "User received YY from lot");
	}

	function test_winning_userReceivesETHPrize() public {
		vm.warp(auctioneerAuction.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneerAuction.getAuction(0).bidData.nextBidBy + 1);
		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;
		uint256 lotPrize = 1e18;
		vm.deal(user1, lotPrice);

		_prepExpectETHBalChange(0, user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "");

		_expectETHBalChange(
			0,
			user1,
			(-1 * int256(lotPrice)) + int256(lotPrize),
			"User 1. Decrease by price increase by prize"
		);
	}
}
