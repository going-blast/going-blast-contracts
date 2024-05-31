// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerBidTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	uint256 runicLot;
	address userG1 = address(1220);
	address userG2 = address(1221);

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_createDefaultDay1Auction();

		runicLot = _createDailyAuctionWithRunes(2, false);

		vm.deal(userG1, 100e18);
		vm.deal(userG2, 100e18);
	}

	function test_bid_RevertWhen_InvalidAuctionLot() public {
		vm.expectRevert(InvalidAuctionLot.selector);
		_bidOnLot(user1, 10);
	}

	function test_bid_RevertWhen_AuctionNotYetOpen() public {
		vm.expectRevert(AuctionNotYetOpen.selector);
		_bidOnLot(user1, 0);
	}

	// EvmError: OutOfFunds
	function testFail_bid_RevertWhen_InsufficientBalance() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		_bidWithOptionsNoDeal(user1, 0, 0, "", 1, PaymentType.WALLET);
	}

	function test_bid_RevertWhen_IncorrectETHValue() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.deal(user1, 10e18);

		vm.expectRevert(IncorrectETHPaymentAmount.selector);

		vm.prank(user1);
		auctioneer.bid{ value: 0 }(0, 0, "", 1, PaymentType.WALLET);

		vm.expectRevert(IncorrectETHPaymentAmount.selector);

		vm.prank(user1);
		auctioneer.bid{ value: 1e18 }(0, 0, "", 1, PaymentType.WALLET);
	}

	function test_bid_RevertWhen_ETHSentWithWrongPaymentType() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.deal(user1, 10e18);

		vm.expectRevert(SentETHButNotWalletPayment.selector);

		vm.prank(user1);
		auctioneer.bid{ value: bidCost }(0, 0, "", 1, PaymentType.VOUCHER);
	}

	function test_bid_ExpectEmit_Bid() public {
		// Set user alias
		_setUserAlias(user1, "XXXX");

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		_expectEmitAuctionEvent_Bid(user1, 0, 0, "Hello World", 1);
		_bidWithOptions(user1, 0, 0, "Hello World", 1, PaymentType.WALLET);
	}

	function test_bid_Should_UpdateAuctionCorrectly() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		Auction memory auctionInit = auctioneerAuction.getAuction(0);

		// Get expected bid
		uint256 expectedBid = startingBid + bidIncrement;

		_bidWithOptions(user1, 0, 0, "Hello World", 1, PaymentType.WALLET);

		Auction memory auction = auctioneerAuction.getAuction(0);

		assertEq(auction.bidData.bidUser, user1, "User is marked as the bidder");
		assertEq(auction.bidData.bidTimestamp, block.timestamp, "Bid timestamp is set correctly");
		assertEq(auction.bidData.revenue, auctionInit.bidData.revenue + bidCost, "Bid cost is added to revenue");
		assertEq(auction.bidData.bid, auctionInit.bidData.bid + bidIncrement, "Bid is incremented by bidIncrement");
		assertEq(auction.bidData.bid, expectedBid, "Bid matches expected bid");
		assertEq(auction.bidData.bids, auctionInit.bidData.bids + 1, "Bid is added to auction bid counter");

		AuctionUser memory auctionUser = auctioneer.getAuctionUser(0, user1);

		assertEq(auctionUser.bids, 1, "Bid is added to user bid counter");
	}

	function test_bid_voucher_Should_UpdateAuctionCorrectly() public {
		_giveVoucher(user1, 10e18);
		_approveVoucher(user1, address(auctioneer), 10e18);

		_warpToUnlockTimestamp(0);
		Auction memory auctionInit = auctioneerAuction.getAuction(0);

		_bidWithOptions(user1, 0, 0, "Hello World", 1, PaymentType.VOUCHER);

		Auction memory auction = auctioneerAuction.getAuction(0);

		assertEq(auction.bidData.bidUser, user1, "User is marked as the bidder");
		assertEq(auction.bidData.bidTimestamp, block.timestamp, "Bid timestamp is set correctly");
		assertEq(auction.bidData.bid, auctionInit.bidData.bid + bidIncrement, "Bid is incremented by bidIncrement");
		assertEq(auction.bidData.bids, auctionInit.bidData.bids + 1, "Bid is added to auction bid counter");

		// Meaningful assertion
		assertEq(auction.bidData.revenue, auctionInit.bidData.revenue, "Revenue should not change");

		AuctionUser memory auctionUser = auctioneer.getAuctionUser(0, user1);

		assertEq(auctionUser.bids, 1, "Bid is added to user bid counter");
	}

	function test_bid_Should_PullBidFromWallet() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.deal(user1, 1e18);

		_prepExpectETHTransfer(0, user1, address(auctioneer));

		_bidWithOptionsNoDeal(user1, 0, 0, "Hello World", 1, PaymentType.WALLET);

		_expectETHTransfer(0, user1, address(auctioneer), bidCost);
	}

	function test_bid_ExpectEmit_Multibid() public {
		uint256 multibid = 9;
		uint256 expectedBid = startingBid + bidIncrement * multibid;
		uint256 expectedCost = bidCost * multibid;

		vm.deal(user1, 10e18);
		uint256 userETHInit = user1.balance;

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		_expectEmitAuctionEvent_Bid(user1, 0, 0, "Hello World", multibid);
		_bidWithOptionsNoDeal(user1, 0, 0, "Hello World", multibid, PaymentType.WALLET);

		Auction memory auction = auctioneerAuction.getAuction(0);

		assertEq(user1.balance, userETHInit - expectedCost, "Expected to pay cost * multibid");
		assertEq(auction.bidData.bid, expectedBid, "Bid updated to match expectedBid");
	}

	// PRIVATE AUCTION
	function _farmDeposit(address payable user, uint256 amount) public {
		_giveGO(user, amount);
		vm.prank(user);
		GO.approve(address(farm), amount);
		vm.prank(user);
		farm.deposit(goPid, amount, user);
	}

	function test_bid_PrivateAuctionRequirement() public {
		// Create private auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		params[0].unlockTimestamp = _getDayInFuture2PMTimestamp(2);
		params[0].isPrivate = true;
		uint256 lot = auctioneerAuction.lotCount();
		auctioneer.createAuctions(params);

		_warpToUnlockTimestamp(lot);

		// USER 1

		// user 1 50 GO staked
		_farmDeposit(user1, 300e18);
		uint256 user1Staked = farm.getEqualizedUserStaked(user1);
		assertGt(user1Staked, auctioneerAuction.privateAuctionRequirement(), "User 1 satisfies private auction req");
		(, , bool permitted) = auctioneer.getUserPrivateAuctionData(user1);
		assertEq(permitted, true, "User 1 permitted");

		// user 1 can bid
		_expectEmitAuctionEvent_Bid(user1, lot, 0, "", 1);
		_bidWithOptions(user1, lot, 0, "", 1, PaymentType.WALLET);

		// USER 2

		// user 2 10 GO staked
		_farmDeposit(user2, 10e18);
		_burnAllGO(user2);
		uint256 user2Staked = farm.getEqualizedUserStaked(user2);
		assertLt(user2Staked, auctioneerAuction.privateAuctionRequirement(), "User 2 does not satisfy private auction req");
		(, , permitted) = auctioneer.getUserPrivateAuctionData(user2);
		assertEq(permitted, false, "User 2 not permitted");

		// user 2 bid revert
		vm.expectRevert(PrivateAuction.selector);

		_bidWithOptions(user2, lot, 0, "", 1, PaymentType.WALLET);

		// USER 3

		// user 3 50 GO held in wallet
		_giveGO(user3, 350e18);
		uint256 user3Held = GO.balanceOf(user3);
		assertGt(user3Held, auctioneerAuction.privateAuctionRequirement(), "User 3 satisfies private auction req");
		(, , permitted) = auctioneer.getUserPrivateAuctionData(user3);
		assertEq(permitted, true, "User 3 permitted");

		// user 3 can bid
		_expectEmitAuctionEvent_Bid(user3, lot, 0, "", 1);
		_bidWithOptions(user3, lot, 0, "", 1, PaymentType.WALLET);

		// USER 4

		// user 4 10 GO held
		_burnAllGO(user4);
		_giveGO(user4, 10e18);
		uint256 user4Held = GO.balanceOf(user4);
		assertLt(user4Held, auctioneerAuction.privateAuctionRequirement(), "User 4 does not satisfy private auction req");
		(, , permitted) = auctioneer.getUserPrivateAuctionData(user4);
		assertEq(permitted, false, "User 4 not permitted");

		// user 2 bid revert
		vm.expectRevert(PrivateAuction.selector);
		_bidWithOptions(user4, lot, 0, "", 1, PaymentType.WALLET);
	}

	// VOUCHER

	function test_bid_Voucher_ExpectRevert_InsufficientBalance() public {
		vm.prank(user1);
		VOUCHER.approve(address(auctioneer), 10e18);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, user1, 0, 1e18));

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		_bidWithOptions(user1, 0, 0, "", 1, PaymentType.VOUCHER);
	}
	function test_bid_Voucher_ExpectRevert_InsufficientAllowance() public {
		_giveVoucher(user1, 10e18);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, 1e18));

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		_bidWithOptions(user1, 0, 0, "", 1, PaymentType.VOUCHER);
	}
	function test_bid_Voucher_ExpectEmit_Bid() public {
		_giveVoucher(user1, 10e18);

		vm.prank(user1);
		VOUCHER.approve(address(auctioneer), 10e18);

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		_expectEmitAuctionEvent_Bid(user1, 0, 0, "", 1);
		_bidWithOptions(user1, 0, 0, "", 1, PaymentType.VOUCHER);
	}
	function test_bid_Voucher_ExpectEmit_Multibid() public {
		_giveVoucher(user1, 10e18);

		vm.prank(user1);
		VOUCHER.approve(address(auctioneer), 10e18);

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		uint256 multibid = 6;

		_expectEmitAuctionEvent_Bid(user1, 0, 0, "", multibid);
		_bidWithOptions(user1, 0, 0, "", multibid, PaymentType.VOUCHER);
	}

	// GAS

	function testFuzz_bid_and_switch(uint256 bidCount) public {
		vm.assume(bidCount > 0 && bidCount < 500);

		_warpToUnlockTimestamp(runicLot);

		vm.prank(userG1);
		auctioneer.bid{ value: bidCost * bidCount }(
			runicLot,
			1,
			"QBSzRNr20LqaavZSowuacuVnobp1LT0b05APlkTFF85i93qJjglVAlrres66bdXT",
			bidCount,
			PaymentType.WALLET
		);

		vm.prank(userG2);
		auctioneer.bid{ value: bidCost * 53 }(
			runicLot,
			2,
			"QBSzRNr2aaaaavZSowuacuVnobp1LT0b05APlkTFF85i93qJjglVAlrres66bdXT",
			53,
			PaymentType.WALLET
		);

		vm.prank(userG1);
		auctioneer.bid{ value: bidCost }(
			runicLot,
			2,
			"QBSzRNr20LqaavZSowuacuVnobp1LT0b05aaakTFF85i93qJjglVAlrres66bdXT",
			1,
			PaymentType.WALLET
		);

		vm.prank(userG1);
		auctioneer.bid{ value: bidCost * 3 }(
			runicLot,
			1,
			"QBSzRNr2aaaaasnthvZSowuacuVnobp1LT0b05APlkTFF85i93qJjglVAlrres66bdXT",
			3,
			PaymentType.WALLET
		);
	}
}
