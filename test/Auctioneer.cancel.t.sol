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
		_setupAuctioneerCreator();
		_giveUsersTokensAndApprove();
	}

	function _expectRevertUnauthorized() public {
		vm.expectRevert(Unauthorized.selector);
	}

	function test_cancelAuction_RevertWhen_CallerIsNotOwner() public {
		_createAuction(_getBaseAuctionParams());

		_expectRevertUnauthorized();

		vm.prank(address(0));
		auctioneer.cancelAuction(0);
	}

	function test_cancelAuction_RevertWhen_InvalidAuctionLot() public {
		_createAuction(_getBaseAuctionParams());

		vm.expectRevert(InvalidAuctionLot.selector);

		_cancelAuction(1);
	}

	function test_cancelAuction_ExpectEmit_AdminCancelAuction() public {
		AuctionParams memory params = _getBaseAuctionParams();
		uint256 lot = _createAuction(params);

		vm.expectEmit(true, true, true, true);
		emit AuctionCancelled(sender, lot);

		auctioneer.cancelAuction(lot);
	}

	function test_cancelAuction_RevertWhen_NotCancellable() public {
		AuctionParams memory params = _getBaseAuctionParams();
		_createAuction(params);

		// User bids
		vm.warp(params.unlockTimestamp);
		_bid(user1);

		// Revert on cancel
		vm.expectRevert(NotCancellable.selector);
		_cancelAuction(0);
	}

	function test_cancelAuction_ExpectEmit_AuctionCancelled() public {
		_createAuction(_getBaseAuctionParams());

		// Event
		vm.expectEmit(true, true, true, true);
		emit AuctionCancelled(creator, 0);

		_cancelAuction(0);
	}

	function test_cancelAuction_Should_ReturnLotToCreator() public {
		AuctionParams memory params = _getBaseAuctionParams();
		_createAuction(params);

		uint256 creatorETH = creator.balance;

		_cancelAuction(0);

		assertEq(
			creator.balance,
			creatorETH + params.tokens[0].amount,
			"Creator balance should increase by auction amount"
		);
	}

	function test_cancelAuction_Should_AdminCancel_ReturnLotToCreator() public {
		AuctionParams memory params = _getBaseAuctionParams();
		_createAuction(params);

		uint256 creatorETH = creator.balance;

		auctioneer.cancelAuction(0);

		assertEq(
			creator.balance,
			creatorETH + params.tokens[0].amount,
			"Creator balance should increase by auction amount"
		);
	}

	function test_cancelAuction_Should_MarkAsFinalized() public {
		_createAuction(_getBaseAuctionParams());

		_cancelAuction(0);

		assertEq(auctioneerAuction.getAuction(0).finalized, true, "Auction should be marked as finalized");
	}

	function test_cancelAuction_RevertWhen_BiddingOnCancelledAuction() public {
		_createAuction(_getBaseAuctionParams());

		_cancelAuction(0);

		// User bids and should revert
		vm.expectRevert(AuctionNotYetOpen.selector);
		_bid(user1);
	}

	function test_cancelAuction_RevertWhen_AlreadyCancelledNotCancellable() public {
		_createAuction(_getBaseAuctionParams());

		_cancelAuction(0);

		vm.expectRevert(NotCancellable.selector);
		_cancelAuction(0);
	}
}
