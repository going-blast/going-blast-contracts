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

contract AuctioneerBidTest is AuctioneerHelper, Test, AuctioneerEvents {
	using SafeERC20 for IERC20;

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

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);

		// For GAS test deposit funds into contract
		vm.prank(user2);
		auctioneer.addFunds(10e18);
	}

	function test_bid_RevertWhen_InvalidAuctionLot() public {
		vm.expectRevert(InvalidAuctionLot.selector);
		auctioneer.bid(1, 1, true);
	}

	function test_bid_RevertWhen_AuctionNotYetOpen() public {
		vm.expectRevert(BiddingClosed.selector);
		auctioneer.bid(0, 1, true);
	}

	function test_bid_RevertWhen_MultibidIs0() public {
		vm.expectRevert(MustBidAtLeastOnce.selector);

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.prank(user1);
		auctioneer.bid(0, 0, true);
	}

	function test_bid_RevertWhen_InsufficientBalance() public {
		uint256 user1UsdBal = USD.balanceOf(user1);
		vm.prank(user1);
		IERC20(USD).safeTransfer(user2, user1UsdBal);

		uint256 bidCost = auctioneer.bidCost();

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, user1, 0, bidCost));

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.prank(user1);
		auctioneer.bid(0, 1, true);
	}

	function test_bid_RevertWhen_InsufficientAllowance() public {
		vm.prank(user1);
		IERC20(USD).approve(address(auctioneer), 0);

		uint256 bidCost = auctioneer.bidCost();

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, bidCost));

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.prank(user1);
		auctioneer.bid(0, 1, true);
	}

	function test_bid_ExpectEmit_Bid() public {
		// Get expected bid
		uint256 expectedBid = auctioneer.startingBid() + auctioneer.bidIncrement();

		// Set user alias
		vm.prank(user1);
		auctioneer.setAlias("XXXX");

		vm.expectEmit(true, true, true, true);
		emit Bid(0, user1, 1, expectedBid, "XXXX");

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.prank(user1);
		auctioneer.bid(0, 1, true);
	}

	function test_bid_Should_UpdateAuctionCorrectly() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		Auction memory auctionInit = auctioneer.getAuction(0);

		vm.prank(user1);
		auctioneer.bid(0, 1, true);

		uint256 bidCost = auctioneer.bidCost();
		uint256 bidIncrement = auctioneer.bidIncrement();
		Auction memory auction = auctioneer.getAuction(0);

		assertEq(auction.bidData.bidUser, user1, "User is marked as the bidder");
		assertEq(auction.bidData.bidTimestamp, block.timestamp, "Bid timestamp is set correctly");
		assertEq(auction.bidData.sum, auctionInit.bidData.sum + bidCost, "Bid cost is added to sum");
		assertEq(auction.bidData.bid, auctionInit.bidData.bid + bidIncrement, "Bid is incremented by bidIncrement");
		assertEq(auction.bidData.bids, auctionInit.bidData.bids + 1, "Bid is added to auction bid counter");

		AuctionUser memory auctionUser = auctioneer.getAuctionUser(0, user1);

		assertEq(auctionUser.bids, 1, "Bid is added to user bid counter");
	}

	function test_bid_Should_PullBidFundsFromWallet() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		uint256 bidCost = auctioneer.bidCost();
		uint256 user1UsdBalInit = USD.balanceOf(user1);
		uint256 auctioneerUsdBalInit = USD.balanceOf(address(auctioneer));

		vm.prank(user1);
		auctioneer.bid(0, 1, true);

		assertEq(USD.balanceOf(user1), user1UsdBalInit - bidCost, "Should remove funds from users wallet");
		assertEq(USD.balanceOf(address(auctioneer)), auctioneerUsdBalInit + bidCost, "Should add funds to auctioneer");
	}

	function test_bid_Should_PullBidFromFunds() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		uint256 bidCost = auctioneer.bidCost();

		// Deposit it wallet (This is tested more fully in Auctioneer.balance.t.sol)
		vm.prank(user1);
		auctioneer.addFunds(10e18);
		uint256 user1UsdBalInit = USD.balanceOf(user1);
		uint256 auctioneerUsdBalInit = USD.balanceOf(address(auctioneer));
		uint256 user1Funds = auctioneer.userFunds(user1);

		vm.prank(user1);
		auctioneer.bid(0, 1, false);

		assertEq(USD.balanceOf(user1), user1UsdBalInit, "Should not remove funds from users wallet");
		assertEq(auctioneer.userFunds(user1), user1Funds - bidCost, "Should remove funds from users balance");
		assertEq(
			USD.balanceOf(address(auctioneer)),
			auctioneerUsdBalInit,
			"Should not add fund to auctioneer from users wallet"
		);
	}

	function test_bid_ExpectEmit_Multibid() public {
		uint256 multibid = 9;
		uint256 expectedBid = auctioneer.startingBid() + auctioneer.bidIncrement() * multibid;
		uint256 expectedCost = auctioneer.getAuction(0).bidData.bidCost * multibid;

		uint256 userUSDInit = USD.balanceOf(user1);

		vm.expectEmit(true, true, true, true);
		emit Bid(0, user1, multibid, expectedBid, "");

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.prank(user1);
		auctioneer.bid(0, multibid, true);

		assertEq(USD.balanceOf(user1), userUSDInit - expectedCost, "Expected to pay cost * multibid");
	}

	function test_bid_GAS_WALLET() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.prank(user1);
		auctioneer.bid(0, 1, true);
	}

	// User 2 has deposited funds into contract
	function test_bid_GAS_BALANCE() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.prank(user2);
		auctioneer.bid(0, 1, false);
	}
}
