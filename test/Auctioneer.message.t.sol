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
		_giveUsersTokensAndApprove();
		_auctioneerUpdateFarm();
		_initializeFarmEmissions();
		_giveTreasuryXXandYYandApprove();

		AuctionParams[] memory params = new AuctionParams[](2);
		// Create single token auction
		params[0] = _getBaseSingleAuctionParams();
		// Create multi token auction
		params[1] = _getMultiTokenSingleAuctionParams();

		// Create single token + nfts auction
		auctioneer.createAuctions(params);
	}

	function test_messageAuction_ExpectEmit() public {
		(uint8 rune, string memory _alias) = auctioneer.getAliasAndRune(0, user1);

		vm.expectEmit(true, true, true, true);
		emit AuctionEvent(0, user1, AuctionEventType.MESSAGE, "TEST TEST TEST", _alias, rune);

		vm.prank(user1);
		auctioneer.messageAuction(0, "TEST TEST TEST");
	}
}
