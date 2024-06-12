// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerCancelTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		_setupAuctioneerTreasury();
		_giveUsersTokensAndApprove();
	}

	function test_cancelAuction_RevertWhen_CallerIsNotOwner() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		_expectRevertNotAdmin(address(0));

		vm.prank(address(0));
		auctioneer.cancelAuction(0);
	}

	function test_cancelAuction_RevertWhen_InvalidAuctionLot() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		vm.expectRevert(InvalidAuctionLot.selector);
		auctioneer.cancelAuction(1);
	}

	function test_cancelAuction_RevertWhen_NotCancellable() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		// User bids
		vm.warp(params.unlockTimestamp);
		_bid(user1);

		// Revert on cancel
		vm.expectRevert(NotCancellable.selector);
		auctioneer.cancelAuction(0);
	}

	function test_cancelAuction_ExpectEmit_AuctionCancelled() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		// Event
		vm.expectEmit(true, true, true, true);
		emit AuctionCancelled(sender, 0);

		auctioneer.cancelAuction(0);
	}

	function test_cancelAuction_Should_ReturnLotToTreasury() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		uint256 treasuryETH = treasury.balance;

		auctioneer.cancelAuction(0);

		assertEq(
			treasury.balance,
			treasuryETH + params.tokens[0].amount,
			"Treasury balance should increase by auction amount"
		);
	}

	function test_cancelAuction_Should_MarkAsFinalized() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		auctioneer.cancelAuction(0);

		assertEq(auctioneerAuction.getAuction(0).finalized, true, "Auction should be marked as finalized");
	}

	function test_cancelAuction_RevertWhen_BiddingOnCancelledAuction() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		auctioneer.cancelAuction(0);

		// User bids and should revert
		vm.expectRevert(AuctionNotYetOpen.selector);
		_bid(user1);
	}

	function test_cancelAuction_RevertWhen_AlreadyCancelledNotCancellable() public {
		AuctionParams memory params = _getBaseAuctionParams();
		auctioneer.createAuction(params);

		auctioneer.cancelAuction(0);

		vm.expectRevert(NotCancellable.selector);
		auctioneer.cancelAuction(0);
	}
}
