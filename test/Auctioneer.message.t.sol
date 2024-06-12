// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils, GBMath } from "../src/AuctionUtils.sol";

contract AuctioneerMessageTest is AuctioneerHelper {
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

	function test_messageAuction_ExpectEmit_BiddingOpenAuction() public {
		_warpToUnlockTimestamp(0);

		_expectEmitAuctionEvent_Message(0, user1, "TEST TEST TEST");

		vm.prank(user1);
		auctioneer.messageAuction(0, "TEST TEST TEST");
	}

	function test_messageAuction_ExpectEmit_PreBidding() public {
		_expectEmitAuctionEvent_Message(0, user1, "TEST TEST TEST");

		vm.prank(user1);
		auctioneer.messageAuction(0, "TEST TEST TEST");
	}

	function test_messageAuction_ExpectRevert_InvalidAuctionLot() public {
		vm.expectRevert(InvalidAuctionLot.selector);

		vm.prank(user1);
		auctioneer.messageAuction(2, "TEST TEST TEST");
	}

	function test_messageAuction_ExpectRevert_AuctionEnded() public {
		_warpToAuctionEndTimestamp(0);

		vm.expectRevert(AuctionEnded.selector);

		vm.prank(user1);
		auctioneer.messageAuction(0, "TEST TEST TEST");
	}
}
