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

contract AuctioneerWinningTest is AuctioneerHelper {
	using SafeERC20 for IERC20;
	using AuctionUtils for Auction;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm();
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

		AuctionParams[] memory params = new AuctionParams[](2);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		// Create multi token auction
		params[1] = _getMultiTokenSingleAuctionParams();

		// Create single token + nfts auction
		auctioneer.createDailyAuctions(params);
	}

	function test_winning_claimAuctionLot_RevertWhen_AuctionStillRunning() public {
		vm.expectRevert(AuctionStillRunning.selector);
		auctioneer.claimAuctionLot(0, true, true);
	}

	function test_winning_claimAuctionLot_ExpectEmit_AuctionLotClaimed() public {
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
		emit AuctionLotClaimed(0, user1, auctioneer.getAuction(0).rewards.tokens, auctioneer.getAuction(0).rewards.amounts);

		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);
	}

	function test_winning_claimLotWinnings_RevertWhen_NotWinner() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);
		assertEq(auctioneer.getAuction(0).bidData.bidUser, user1, "User1 won auction");

		// User2 claim reverted
		vm.expectRevert(NotWinner.selector);
		vm.prank(user2);
		auctioneer.claimAuctionLot(0, true, true);
	}

	function test_winning_claimLotWinnings_RevertWhen_AuctionLotAlreadyClaimed() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		// Claim once
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);
		assertEq(auctioneer.getAuction(0).claimed, true, "Auction marked as claimed");

		// Revert on claim again
		vm.expectRevert(AuctionLotAlreadyClaimed.selector);
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);
	}

	function test_winning_winnerCanPayForLotFromWallet() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		uint256 lotPrice = auctioneer.getAuction(0).bidData.bid;
		uint256 user1USDBalInit = USD.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);

		uint256 user1USDBalFinal = USD.balanceOf(user1);

		assertEq(user1USDBalInit - lotPrice, user1USDBalFinal, "Users USD balance should decrease by lot price");
	}

	function test_winning_winnerCanPayForLotFromFunds() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		// Deposit into funds
		vm.prank(user1);
		auctioneer.addFunds(50e18);

		uint256 lotPrice = auctioneer.getAuction(0).bidData.bid;
		uint256 user1USDBalInit = USD.balanceOf(user1);
		uint256 user1FundsInit = auctioneer.userFunds(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, false, true);

		uint256 user1USDBalFinal = USD.balanceOf(user1);
		uint256 user1FundsFinal = auctioneer.userFunds(user1);

		assertEq(user1USDBalInit, user1USDBalFinal, "Users USD balance should not change");
		assertEq(user1FundsInit - lotPrice, user1FundsFinal, "Users finds should decrease by lot price");
	}

	function test_winning_partialLotPaymentTakenFromFunds() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		uint256 lotPrice = auctioneer.getAuction(0).bidData.bid;

		// Deposit into funds
		vm.prank(user1);
		auctioneer.addFunds(lotPrice / 2);

		uint256 user1USDBalInit = USD.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, false, true);

		uint256 user1USDBalFinal = USD.balanceOf(user1);
		uint256 user1FundsFinal = auctioneer.userFunds(user1);

		assertEq(user1USDBalInit - (lotPrice / 2), user1USDBalFinal, "Users USD balance should decrease by lot price / 2");
		assertEq(user1FundsFinal, 0, "Users funds should be depleted");
	}

	function test_winning_lotPriceIsDistributedCorrectly() public {
		// Set farm
		auctioneer.setFarm(address(farm));

		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_multibid(user2, 58);
		_multibid(user3, 152);
		_multibid(user4, 96);
		_multibid(user1, 110);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		// Finalize to distribute bidding revenue
		auctioneer.finalizeAuction(0);

		uint256 lotPrice = auctioneer.getAuction(0).bidData.bid;
		uint256 treasuryUSDInit = USD.balanceOf(treasury);
		uint256 farmUSDInit = USD.balanceOf(address(farm));
		uint256 treasurySplit = auctioneer.treasurySplit();

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, false, true);

		uint256 treasuryUSDFinal = USD.balanceOf(treasury);
		uint256 farmUSDFinal = USD.balanceOf(address(farm));

		assertEq(treasuryUSDFinal - treasuryUSDInit, (lotPrice * treasurySplit) / 10000, "Treasury should receive share");
		assertEq(farmUSDFinal - farmUSDInit, (lotPrice * (10000 - treasurySplit)) / 10000, "Farm should receive share");
		assertEq(
			((treasuryUSDFinal - treasuryUSDInit) * 10000) / treasurySplit,
			((farmUSDFinal - farmUSDInit) * 10000) / (10000 - treasurySplit),
			"Farm and treasury receive correct split"
		);
	}

	function test_winning_auctionIsMarkedAsClaimed() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);
		assertEq(auctioneer.getAuction(0).claimed, true, "Auction marked as claimed");
	}

	function test_winning_userReceivesLotTokens() public {
		vm.warp(auctioneer.getAuction(1).unlockTimestamp);
		_bidOnLot(user1, 1);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(1).bidData.nextBidBy + 1);

		// Tokens init
		uint256 userETHInit = user1.balance;
		uint256 userXXInit = XXToken.balanceOf(user1);
		uint256 userYYInit = YYToken.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(1, true, true);

		// User received lot
		Auction memory auction = auctioneer.getAuction(1);
		assertEq(user1.balance - userETHInit, auction.rewards.amounts[0], "User received ETH from lot");
		assertEq(XXToken.balanceOf(user1) - userXXInit, auction.rewards.amounts[1], "User received XX from lot");
		assertEq(YYToken.balanceOf(user1) - userYYInit, auction.rewards.amounts[2], "User received YY from lot");
	}

	function test_winning_userCanChooseLotAsEth() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		// ETH bal
		uint256 userETHInit = user1.balance;

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, true);

		// ETH test
		assertEq(user1.balance - userETHInit, auctioneer.getAuction(0).rewards.amounts[0], "User received ETH from lot");
	}
	function test_winning_userCanChooseLotAsWeth() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);
		_bid(user1);

		// Claimable after next bid by
		vm.warp(auctioneer.getAuction(0).bidData.nextBidBy + 1);

		// ETH bal
		uint256 userWETHInit = WETH.balanceOf(user1);

		// Claim
		vm.prank(user1);
		auctioneer.claimAuctionLot(0, true, false);

		// ETH test
		assertEq(
			WETH.balanceOf(user1) - userWETHInit,
			auctioneer.getAuction(0).rewards.amounts[0],
			"User received WETH from lot"
		);
	}
}
