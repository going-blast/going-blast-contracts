// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerBidTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_createDefaultDay1Auction();

		// For GAS test deposit funds into contract
		_addUserFunds(user2, 10e18);
	}

	function test_bid_RevertWhen_InvalidAuctionLot() public {
		vm.expectRevert(InvalidAuctionLot.selector);
		_bidOnLot(user1, 1);
	}

	function test_bid_RevertWhen_AuctionNotYetOpen() public {
		vm.expectRevert(AuctionNotYetOpen.selector);
		_bidOnLot(user1, 0);
	}

	// EvmError: OutOfFunds
	function testFail_bid_RevertWhen_InsufficientBalance() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		_bidWithOptionsNoDeal(user1, 0, BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: 0 }));
	}

	function test_bid_RevertWhen_IncorrectETHValue() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.deal(user1, 10e18);

		vm.expectRevert(IncorrectETHPaymentAmount.selector);

		vm.prank(user1);
		auctioneer.bid{ value: 0 }(0, BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: 0 }));

		vm.expectRevert(IncorrectETHPaymentAmount.selector);

		vm.prank(user1);
		auctioneer.bid{ value: 1e18 }(
			0,
			BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: 0 })
		);
	}

	function test_bid_RevertWhen_ETHSentWithWrongPaymentType() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.deal(user1, 10e18);

		vm.expectRevert(SentETHButNotWalletPayment.selector);

		vm.prank(user1);
		auctioneer.bid{ value: bidCost }(
			0,
			BidOptions({ paymentType: PaymentType.FUNDS, multibid: 1, message: "", rune: 0 })
		);

		vm.expectRevert(SentETHButNotWalletPayment.selector);

		vm.prank(user1);
		auctioneer.bid{ value: bidCost }(
			0,
			BidOptions({ paymentType: PaymentType.VOUCHER, multibid: 1, message: "", rune: 0 })
		);
	}

	function test_bid_ExpectEmit_Bid() public {
		// Get expected bid
		uint256 expectedBid = startingBid + bidIncrement;

		// Set user alias
		_setUserAlias(user1, "XXXX");

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		vm.expectEmit(true, true, true, true);
		BidOptions memory options = BidOptions({
			paymentType: PaymentType.WALLET,
			multibid: 1,
			message: "Hello World",
			rune: 0
		});
		emit Bid(0, user1, expectedBid, "XXXX", options, block.timestamp);

		_bidWithOptions(user1, 0, options);
	}

	function test_bid_Should_UpdateAuctionCorrectly() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		Auction memory auctionInit = auctioneerAuction.getAuction(0);

		BidOptions memory options = BidOptions({
			paymentType: PaymentType.WALLET,
			multibid: 1,
			message: "Hello World",
			rune: 0
		});
		_bidWithOptions(user1, 0, options);

		Auction memory auction = auctioneerAuction.getAuction(0);

		assertEq(auction.bidData.bidUser, user1, "User is marked as the bidder");
		assertEq(auction.bidData.bidTimestamp, block.timestamp, "Bid timestamp is set correctly");
		assertEq(auction.bidData.revenue, auctionInit.bidData.revenue + bidCost, "Bid cost is added to revenue");
		assertEq(auction.bidData.bid, auctionInit.bidData.bid + bidIncrement, "Bid is incremented by bidIncrement");
		assertEq(auction.bidData.bids, auctionInit.bidData.bids + 1, "Bid is added to auction bid counter");

		AuctionUser memory auctionUser = auctioneerUser.getAuctionUser(0, user1);

		assertEq(auctionUser.bids, 1, "Bid is added to user bid counter");
	}

	function test_bid_voucher_Should_UpdateAuctionCorrectly() public {
		_giveVoucher(user1, 10e18);
		_approveVoucher(user1, address(auctioneer), 10e18);

		_warpToUnlockTimestamp(0);
		Auction memory auctionInit = auctioneerAuction.getAuction(0);

		BidOptions memory options = BidOptions({
			paymentType: PaymentType.VOUCHER,
			multibid: 1,
			message: "Hello World",
			rune: 0
		});
		_bidWithOptions(user1, 0, options);

		Auction memory auction = auctioneerAuction.getAuction(0);

		assertEq(auction.bidData.bidUser, user1, "User is marked as the bidder");
		assertEq(auction.bidData.bidTimestamp, block.timestamp, "Bid timestamp is set correctly");
		assertEq(auction.bidData.bid, auctionInit.bidData.bid + bidIncrement, "Bid is incremented by bidIncrement");
		assertEq(auction.bidData.bids, auctionInit.bidData.bids + 1, "Bid is added to auction bid counter");

		// Meaningful assertion
		assertEq(auction.bidData.revenue, auctionInit.bidData.revenue, "Revenue should not change");

		AuctionUser memory auctionUser = auctioneerUser.getAuctionUser(0, user1);

		assertEq(auctionUser.bids, 1, "Bid is added to user bid counter");
	}

	function test_bid_Should_PullBidFundsFromWallet() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.deal(user1, 1e18);

		_prepExpectETHTransfer(0, user1, address(auctioneer));

		BidOptions memory options = BidOptions({
			paymentType: PaymentType.WALLET,
			multibid: 1,
			message: "Hello World",
			rune: 0
		});
		_bidWithOptionsNoDeal(user1, 0, options);

		_expectETHTransfer(0, user1, address(auctioneer), bidCost);
	}

	function test_bid_Should_PullBidFromFunds() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		// Deposit it wallet (This is tested more fully in Auctioneer.balance.t.sol)
		_addUserFunds(user1, 10e18);
		uint256 user1EthBalInit = user1.balance;
		uint256 auctioneerEthBalInit = address(auctioneer).balance;
		uint256 user1Funds = auctioneerUser.userFunds(user1);

		BidOptions memory options = BidOptions({
			paymentType: PaymentType.FUNDS,
			multibid: 1,
			message: "Hello World",
			rune: 0
		});
		_bidWithOptions(user1, 0, options);

		assertEq(user1.balance, user1EthBalInit, "Should not remove funds from users wallet");
		assertEq(auctioneerUser.userFunds(user1), user1Funds - bidCost, "Should remove funds from users balance");
		assertEq(address(auctioneer).balance, auctioneerEthBalInit, "Should not add fund to auctioneer from users wallet");
	}

	function test_bid_ExpectEmit_Multibid() public {
		uint256 multibid = 9;
		uint256 expectedBid = startingBid + bidIncrement * multibid;
		uint256 expectedCost = bidCost * multibid;

		vm.deal(user1, 10e18);
		uint256 userETHInit = user1.balance;

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		vm.expectEmit(true, true, true, true);
		BidOptions memory options = BidOptions({
			paymentType: PaymentType.WALLET,
			multibid: multibid,
			message: "Hello World",
			rune: 0
		});
		emit Bid(0, user1, expectedBid, "", options, block.timestamp);

		_bidWithOptionsNoDeal(user1, 0, options);

		assertEq(user1.balance, userETHInit - expectedCost, "Expected to pay cost * multibid");
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
		auctioneer.createAuctions(params);

		// Warp to private auction unlock
		vm.warp(params[0].unlockTimestamp + 1 hours);

		// USER 1

		// user 1 50 GO staked
		_farmDeposit(user1, 300e18);
		uint256 user1Staked = farm.getEqualizedUserStaked(user1);
		assertGt(user1Staked, auctioneerAuction.privateAuctionRequirement(), "User 1 satisfies private auction req");
		(, , bool permitted) = auctioneer.getUserPrivateAuctionData(user1);
		assertEq(permitted, true, "User 1 permitted");

		// user 1 can bid
		uint256 expectedBid = auctioneerAuction.startingBid() + auctioneerAuction.bidIncrement();
		vm.expectEmit(true, true, true, true);
		BidOptions memory options = BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: 0 });
		emit Bid(1, user1, expectedBid, "", options, block.timestamp);

		_bidWithOptions(user1, 1, options);

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

		options = BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: 0 });
		_bidWithOptions(user2, 1, options);

		// USER 3

		// user 3 50 GO held in wallet
		_giveGO(user3, 350e18);
		uint256 user3Held = GO.balanceOf(user3);
		assertGt(user3Held, auctioneerAuction.privateAuctionRequirement(), "User 3 satisfies private auction req");
		(, , permitted) = auctioneer.getUserPrivateAuctionData(user3);
		assertEq(permitted, true, "User 3 permitted");

		// user 3 can bid
		expectedBid = auctioneerAuction.getAuction(1).bidData.bid + auctioneerAuction.bidIncrement();
		vm.expectEmit(true, true, true, true);
		options = BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: 0 });
		emit Bid(1, user3, expectedBid, "", options, block.timestamp);

		_bidWithOptions(user3, 1, options);

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

		_bidWithOptions(user4, 1, options);
	}

	// VOUCHER

	function test_bid_Voucher_ExpectRevert_InsufficientBalance() public {
		vm.prank(user1);
		VOUCHER.approve(address(auctioneer), 10e18);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, user1, 0, 1e18));

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		BidOptions memory options = BidOptions({ paymentType: PaymentType.VOUCHER, multibid: 1, message: "", rune: 0 });
		_bidWithOptions(user1, 0, options);
	}
	function test_bid_Voucher_ExpectRevert_InsufficientAllowance() public {
		_giveVoucher(user1, 10e18);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, 1e18));

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		BidOptions memory options = BidOptions({ paymentType: PaymentType.VOUCHER, multibid: 1, message: "", rune: 0 });
		_bidWithOptions(user1, 0, options);
	}
	function test_bid_Voucher_ExpectEmit_Bid() public {
		_giveVoucher(user1, 10e18);

		vm.prank(user1);
		VOUCHER.approve(address(auctioneer), 10e18);

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		uint256 expectedBid = auctioneerAuction.startingBid() + auctioneerAuction.bidIncrement();
		vm.expectEmit(true, true, true, true);

		BidOptions memory options = BidOptions({ paymentType: PaymentType.VOUCHER, multibid: 1, message: "", rune: 0 });
		emit Bid(0, user1, expectedBid, "", options, block.timestamp);

		_bidWithOptions(user1, 0, options);
	}
	function test_bid_Voucher_ExpectEmit_Multibid() public {
		_giveVoucher(user1, 10e18);

		vm.prank(user1);
		VOUCHER.approve(address(auctioneer), 10e18);

		vm.warp(_getNextDay2PMTimestamp() + 1 hours);

		uint256 multibid = 6;
		uint256 expectedBid = auctioneerAuction.startingBid() + auctioneerAuction.bidIncrement() * multibid;
		vm.expectEmit(true, true, true, true);

		BidOptions memory options = BidOptions({
			paymentType: PaymentType.VOUCHER,
			multibid: multibid,
			message: "",
			rune: 0
		});
		emit Bid(0, user1, expectedBid, "", options, block.timestamp);

		_bidWithOptions(user1, 0, options);
	}

	// GAS

	function test_bid_GAS_WALLET() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		BidOptions memory options = BidOptions({ paymentType: PaymentType.WALLET, multibid: 1, message: "", rune: 0 });
		_bidWithOptions(user1, 0, options);
	}

	// User 2 has deposited funds into contract
	function test_bid_GAS_FUNDS() public {
		vm.warp(_getNextDay2PMTimestamp() + 1 hours);
		BidOptions memory options = BidOptions({ paymentType: PaymentType.FUNDS, multibid: 1, message: "", rune: 0 });
		_bidWithOptions(user2, 0, options);
	}
}
