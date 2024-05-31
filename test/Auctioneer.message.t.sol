// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils, GBMath } from "../src/AuctionUtils.sol";

contract AuctioneerMessageTest is AuctioneerHelper {
	using GBMath for uint256;
	using SafeERC20 for IERC20;
	using AuctionViewUtils for Auction;

	function setUp() public override {
		super.setUp();

		_distributeGO();
		_initializeAuctioneerEmissions();
		_setupAuctioneerTreasury();
		_setupAuctioneerTeamTreasury();
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_giveTreasuryXXandYYandApprove();

		AuctionParams[] memory params = new AuctionParams[](2);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		// Create multi token auction
		params[1] = _getBaseSingleAuctionParams();
		params[1].isPrivate = true;

		auctioneer.createAuctions(params);
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

	function test_messageAuction_ExpectRevert_PrivateAuction() public {
		_warpToUnlockTimestamp(1);

		vm.expectRevert(PrivateAuction.selector);

		vm.prank(user1);
		auctioneer.messageAuction(1, "TEST TEST TEST");

		_giveGO(user1, 300e18);

		_expectEmitAuctionEvent_Message(1, user1, "TEST TEST TEST");

		vm.prank(user1);
		auctioneer.messageAuction(1, "TEST TEST TEST");
	}
}
