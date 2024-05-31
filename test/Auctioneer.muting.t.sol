// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AuctionViewUtils, GBMath } from "../src/AuctionUtils.sol";

contract AuctioneerMutingTest is AuctioneerHelper {
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
		_createDefaultDay1Auction();
	}

	/*



- [ ] Muted users tests
  - [ ] Add "mods" to allow moderating the chat
  - [ ] updated in state
  - [ ] Can update whether a user is muted
  - [ ] Only admin can mute user
  - [ ] Muting a user removes their alias
  - [ ] Message Auction
    - [ ] Revert if user muted with "Muted"
  - [ ] Bid
    - [ ] Unmuted user can send message with alias
    - [ ] Muted users message and alias removed
  - [ ] SelectRune
    - [ ] Unmuted user can send message with alias
    - [ ] Muted users message and alias removed
  - [ ] Claimed
    - [ ] Unmuted user can send message with alias
    - [ ] Muted users message and alias removed
  - [ ] Set Alias reverts if muted


	*/

	function _expectEmitMutedUser(address user, bool muted) public {
		vm.expectEmit(true, true, true, true);
		emit MutedUser(user, muted);
	}

	function test_muteUser_AccessControl_AdminYes_ModYes_ElseNo() public {
		_expectRevertNotModerator(user1);
		vm.prank(user1);
		auctioneer.muteUser(user2, true);

		auctioneer.grantRole(MOD_ROLE, user1);

		_expectEmitMutedUser(user2, true);
		vm.prank(user1);
		auctioneer.muteUser(user2, true);

		_expectEmitMutedUser(user3, true);
		auctioneer.muteUser(user3, true);
	}

	function test_muteUser_ExpectEmit() public {
		vm.expectEmit(true, true, true, true);
		emit MutedUser(user1, true);

		auctioneer.muteUser(user1, true);

		vm.expectEmit(true, true, true, true);
		emit MutedUser(user1, false);

		auctioneer.muteUser(user1, false);
	}
	function test_muteUser_RemovesAlias() public {
		vm.prank(user1);
		auctioneer.setAlias("BADWORD");

		assertEq(auctioneer.userAlias(user1), "BADWORD", "User set alias");
		assertEq(auctioneer.mutedUsers(user1), false, "User is not yet muted");

		auctioneer.muteUser(user1, true);

		assertEq(auctioneer.userAlias(user1), "", "User alias has been removed");
		assertEq(auctioneer.mutedUsers(user1), true, "User has been muted");
	}
	function test_mutedUser_MessageAuction_ExpectRevert_Muted() public {
		auctioneer.muteUser(user1, true);

		vm.expectRevert(Muted.selector);
		vm.prank(user1);
		auctioneer.messageAuction(0, "MUTED MUTED MUTED");

		vm.expectEmit(true, true, true, true);
		emit Messaged(0, user2, "FREE FREE FREE", "", 0);
		vm.prank(user2);
		auctioneer.messageAuction(0, "FREE FREE FREE");
	}
	function test_mutedUser_SetAlias_ExpectRevert_Muted() public {
		auctioneer.muteUser(user1, true);

		vm.expectRevert(Muted.selector);
		vm.prank(user1);
		auctioneer.setAlias("BAD-BAD");

		vm.expectEmit(true, true, true, true);
		emit UpdatedAlias(user2, "GOOD-GOOD");
		vm.prank(user2);
		auctioneer.setAlias("GOOD-GOOD");
	}
	function test_mutedUser_Bid_ExpectCensored() public {
		auctioneer.muteUser(user1, true);

		_warpToUnlockTimestamp(0);

		_expectEmitAuctionEvent_Bid(0, user1, "", 0, 1);
		_bidWithOptions(
			user1,
			0,
			BidOptions({ paymentType: PaymentType.WALLET, message: "IM A BAD GUY", rune: 0, multibid: 1 })
		);

		_expectEmitAuctionEvent_Bid(0, user2, "IM A GOOD GUY", 0, 1);
		_bidWithOptions(
			user2,
			0,
			BidOptions({ paymentType: PaymentType.WALLET, message: "IM A GOOD GUY", rune: 0, multibid: 1 })
		);
	}
	function test_mutedUser_SelectRune_ExpectCensored() public {
		uint256 lot = _createDailyAuctionWithRunes(2, true);

		auctioneer.muteUser(user1, true);

		_expectEmitAuctionEvent_SwitchRune(lot, user1, "", 1);
		vm.prank(user1);
		auctioneer.selectRune(lot, 1, "IM A BAD GUY");

		_expectEmitAuctionEvent_SwitchRune(lot, user2, "IM A GOOD GUY", 1);
		vm.prank(user2);
		auctioneer.selectRune(lot, 1, "IM A GOOD GUY");
	}
	function test_mutedUser_Claimed_ExpectCensored() public {
		auctioneer.muteUser(user1, true);

		_warpToUnlockTimestamp(0);
		_bidOnLot(user1, 0);
		_warpToAuctionEndTimestamp(0);

		_expectEmitAuctionEvent_Claim(0, user1, "");

		uint256 lotPrice = auctioneerAuction.getAuction(0).bidData.bid;

		vm.deal(user1, 1e18);
		vm.prank(user1);
		auctioneer.claimLot{ value: lotPrice }(0, "SUCK MY D**K A******S");
	}
}
