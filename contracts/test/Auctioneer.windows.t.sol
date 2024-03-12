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

contract AuctioneerWindowsTest is AuctioneerHelper, Test, AuctioneerEvents {
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
	}

	/*

  [ ] Auction does not end during open window
  [ ] Ends during timed window if timer expires
  [ ] Timed windows can end
  [ ] Infinite windows cannot end
  [ ] Transition from open window -> open window -> timed window -> timed window -> infinite window (covers all possibilities)

	*/

	function _bidShouldRevert(address user) public {
		vm.expectRevert(BiddingClosed.selector);
		_bid(user);
	}
	function _bidShouldEmit(address user) public {
		uint256 expectedBid = auctioneer.getAuction(0).bidData.bid + auctioneer.bidIncrement();
		vm.expectEmit(true, true, true, true);
		emit Bid(0, user, 1, expectedBid, "");
		_bid(user);
	}
	function _bid(address user) public {
		vm.prank(user);
		auctioneer.bid(0, 1, true);
	}
	function _bidUntil(address user, uint256 timer, uint256 until) public {
		while (true) {
			if (block.timestamp > until) return;
			vm.warp(block.timestamp + timer);
			_bid(user);
		}
	}

	function test_windows_nextBidBy_PreUnlock() public {
		assertEq(auctioneer.exposed_auction_activeWindow(0), -1, "Before auction unlocks active window is -1");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), false, "Before auction unlocks, bidding closed");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Before action unlocks, not closed");

		uint256 nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		uint256 expectedNextBidBy = auctioneer.getAuction(0).windows[0].windowCloseTimestamp +
			auctioneer.getAuction(0).windows[1].timer;

		assertEq(
			nextBidBy,
			expectedNextBidBy,
			"Before unlock, nextBidBy: windowOpenTimestamp of first timed window + timer"
		);
	}

	function test_windows_nextBidBy_OpenWindow() public {
		vm.warp(auctioneer.getAuction(0).unlockTimestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 0, "Auction unlocked, active window is 0");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction unlocked, bidding open");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Auction unlocked, not closed");

		uint256 nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		uint256 expectedNextBidBy = auctioneer.getAuction(0).windows[0].windowCloseTimestamp +
			auctioneer.getAuction(0).windows[1].timer;

		assertEq(nextBidBy, expectedNextBidBy, "OPEN window, nextBidBy: windowOpenTimestamp of first timed window + timer");

		// Bidding should not change nextBidBy
		_bidShouldEmit(user1);

		uint256 nextBidBy2 = auctioneer.getAuction(0).bidData.nextBidBy;
		assertEq(nextBidBy2, expectedNextBidBy, "OPEN window, bidding should not change nextBidBy");
	}

	function test_windows_nextBidBy_TimedWindow() public {
		vm.warp(auctioneer.getAuction(0).windows[0].windowCloseTimestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 1, "Auction open window ended, active window is 1 (timed)");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction open window ended, bidding open");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Auction open window ended, not closed");

		uint256 windowTimer = auctioneer.getAuction(0).windows[1].timer;
		uint256 nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		uint256 expectedNextBidBy = auctioneer.getAuction(0).windows[0].windowCloseTimestamp + windowTimer;

		assertEq(
			nextBidBy,
			expectedNextBidBy,
			"TIMED window, nextBidBy: windowOpenTimestamp of first timed window + timer"
		);

		vm.warp(block.timestamp + 20);
		// Bidding should change nextBidBy
		_bidShouldEmit(user1);

		nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		expectedNextBidBy = block.timestamp + windowTimer;
		assertEq(nextBidBy, expectedNextBidBy, "TIMED window, bidding should increase nextBidBy");
		console.log("User Bid :: timestamp: %s, next bid by: %s", block.timestamp, nextBidBy);

		vm.warp(block.timestamp + 60);
		// Bidding should change nextBidBy
		_bidShouldEmit(user1);

		nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		expectedNextBidBy = block.timestamp + windowTimer;
		assertEq(nextBidBy, expectedNextBidBy, "TIMED window, bidding should increase nextBidBy");
		console.log("User Bid :: timestamp: %s, next bid by: %s", block.timestamp, nextBidBy);
	}

	function test_windows_nextBidBy_BiddingCloses_WhenNextBidByPassed() public {
		vm.warp(auctioneer.getAuction(0).windows[0].windowCloseTimestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 1, "Auction open window ended, active window is 1 (timed)");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction open window ended, bidding open");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Auction open window ended, not closed");

		uint256 windowTimer = auctioneer.getAuction(0).windows[1].timer;
		uint256 nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		uint256 expectedNextBidBy = auctioneer.getAuction(0).windows[0].windowCloseTimestamp + windowTimer;

		assertEq(
			nextBidBy,
			expectedNextBidBy,
			"TIMED window, nextBidBy: windowOpenTimestamp of first timed window + timer"
		);

		for (uint256 i = block.timestamp; i <= nextBidBy + 3; i++) {
			vm.warp(i);
			if (i <= nextBidBy) {
				assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Time tick bidding open");
				assertEq(auctioneer.exposed_auction_isClosed(0), false, "Time tick bidding not closed");
			} else {
				assertEq(auctioneer.exposed_auction_isBiddingOpen(0), false, "Time tick bidding not open");
				assertEq(auctioneer.exposed_auction_isClosed(0), true, "Time tick bidding closed");
				_bidShouldRevert(user1);
			}
		}
	}

	function test_windows_IntegrationTest() public {
		assertEq(auctioneer.exposed_auction_activeWindow(0), -1, "Before auction unlocks active window is -1");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), false, "Before auction unlocks, bidding closed");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Before action unlocks, not closed");

		_bidShouldRevert(user1);

		// Warp to open window
		uint256 timestamp = auctioneer.getAuction(0).unlockTimestamp;
		console.log("Unlock timestamp: %s", timestamp);
		vm.warp(timestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 0, "Auction unlocked, active window is 0");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction unlocked, bidding open");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Auction unlocked, not closed");
		console.log(
			"Timestamp %s, window %s, closesAtTimestamp %s",
			block.timestamp,
			uint8(auctioneer.exposed_auction_activeWindow(0)),
			auctioneer.exposed_auction_activeWindowClosesAtTimestamp(0)
		);

		_bidShouldEmit(user1);

		// Warp within open window
		timestamp += 1 hours;
		vm.warp(timestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 0, "Auction unlocked, active window is 0 (open)");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction unlocked, bidding open");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Auction unlocked, not closed");

		_bidShouldEmit(user1);

		// Warp to end of window
		timestamp = auctioneer.getAuction(0).windows[0].windowCloseTimestamp;
		vm.warp(timestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 1, "Auction open window ended, active window is 1 (timed)");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction open window ended, bidding open");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Auction open window ended, not closed");

		// Bid until end of window
		timestamp = auctioneer.getAuction(0).windows[1].windowCloseTimestamp;
		uint256 timer = auctioneer.getAuction(0).windows[1].timer;
		_bidUntil(user1, timer / 2, timestamp);

		assertEq(
			auctioneer.exposed_auction_activeWindow(0),
			2,
			"Auction timed window ended, active window is 2 (infinite)"
		);
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction open window ended, bidding open");
		assertEq(auctioneer.exposed_auction_isClosed(0), false, "Auction open window ended, not closed");

		// Bid for 1 more hour
		timestamp += 1 hours;
		_bidUntil(user1, timer / 2, timestamp);
	}

	function test_openWindow_BiddingOpen() public {}
}
