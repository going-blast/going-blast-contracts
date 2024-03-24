// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils } from "../src/AuctionUtils.sol";

contract AuctioneerWindowsTest is AuctioneerHelper {
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneer();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_createDefaultDay1Auction();
	}

	function test_windows_nextBidBy_PreUnlock() public {
		assertEq(auctioneer.exposed_auction_activeWindow(0), 0, "Before auction unlocks active window is 0");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), false, "Before auction unlocks, bidding closed");
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Before action unlocks, not closed");

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
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Auction unlocked, not closed");

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
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Auction open window ended, not closed");

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
		// console.log("User Bid :: timestamp: %s, next bid by: %s", block.timestamp, nextBidBy);

		vm.warp(block.timestamp + 60);
		// Bidding should change nextBidBy
		_bidShouldEmit(user1);

		nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		expectedNextBidBy = block.timestamp + windowTimer;
		assertEq(nextBidBy, expectedNextBidBy, "TIMED window, bidding should increase nextBidBy");
		// console.log("User Bid :: timestamp: %s, next bid by: %s", block.timestamp, nextBidBy);
	}

	function test_windows_nextBidBy_BiddingCloses_WhenNextBidByPassed() public {
		vm.warp(auctioneer.getAuction(0).windows[0].windowCloseTimestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 1, "Auction open window ended, active window is 1 (timed)");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction open window ended, bidding open");
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Auction open window ended, not closed");

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
				assertEq(auctioneer.exposed_auction_isEnded(0), false, "Time tick bidding not closed");
			} else {
				assertEq(auctioneer.exposed_auction_isBiddingOpen(0), false, "Time tick bidding not open");
				assertEq(auctioneer.exposed_auction_isEnded(0), true, "Time tick bidding closed");
				_bidShouldRevert(user1);
			}
		}
	}

	function test_windows_IntegrationTest() public {
		assertEq(auctioneer.exposed_auction_activeWindow(0), 0, "Before auction unlocks active window is 0");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), false, "Before auction unlocks, bidding closed");
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Before action unlocks, not closed");

		_bidShouldRevert(user1);

		// Warp to open window
		uint256 timestamp = auctioneer.getAuction(0).unlockTimestamp;
		// console.log("Unlock timestamp: %s", timestamp);
		vm.warp(timestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 0, "Auction unlocked, active window is 0");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction unlocked, bidding open");
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Auction unlocked, not closed");

		_bidShouldEmit(user1);

		// Warp within open window
		timestamp += 1 hours;
		vm.warp(timestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 0, "Auction unlocked, active window is 0 (open)");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction unlocked, bidding open");
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Auction unlocked, not closed");

		_bidShouldEmit(user1);

		// Warp to end of window
		timestamp = auctioneer.getAuction(0).windows[0].windowCloseTimestamp;
		vm.warp(timestamp);

		assertEq(auctioneer.exposed_auction_activeWindow(0), 1, "Auction open window ended, active window is 1 (timed)");
		assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Auction open window ended, bidding open");
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Auction open window ended, not closed");

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
		assertEq(auctioneer.exposed_auction_isEnded(0), false, "Auction open window ended, not closed");

		// Bid for 1 more hour
		timestamp += 1 hours;
		_bidUntil(user1, timer / 2, timestamp);

		// Let bid lapse
		uint256 nextBidBy = auctioneer.getAuction(0).bidData.nextBidBy;
		for (uint256 i = block.timestamp; i <= nextBidBy + 1; i++) {
			vm.warp(i);
			if (i <= nextBidBy) {
				assertEq(auctioneer.exposed_auction_isBiddingOpen(0), true, "Time tick bidding open");
				assertEq(auctioneer.exposed_auction_isEnded(0), false, "Time tick bidding not closed");
			} else {
				assertEq(auctioneer.exposed_auction_isBiddingOpen(0), false, "Time tick bidding not open");
				assertEq(auctioneer.exposed_auction_isEnded(0), true, "Time tick bidding closed");
				_bidShouldRevert(user1);
			}
		}

		// Finalize auction
		vm.expectEmit(true, true, true, true);
		emit AuctionFinalized(0);
		auctioneer.finalizeAuction(0);
	}
}
