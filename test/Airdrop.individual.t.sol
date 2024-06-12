// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ClaimableAirdropIndividual } from "../src/ClaimableAirdrop.sol";

contract AirdropIndividualTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	ClaimableAirdropIndividual public indiv1;

	function setUp() public override {
		super.setUp();

		indiv1 = new ClaimableAirdropIndividual(VOUCHER, treasury, "INDIV_1");
	}

	event AddedUsers(address[] users, uint256[] amounts);
	event ClosedAirdrop(bool closed);
	event Claimed(address indexed to, uint256 amount);

	error LengthMismatch();
	error Closed();
	error NothingToClaim();
	error AlreadyClaimed();

	function test_addUsers_RevertWhen_NotOwner() public {
		address[] memory aUsers = new address[](1);
		uint256[] memory aAmounts = new uint256[](1);
		aUsers[0] = user1;
		aAmounts[0] = 100e18;

		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1));

		vm.prank(user1);
		indiv1.addUsers(aUsers, aAmounts);
	}

	function test_addUsers_ExpectEmit_AddedUsers() public {
		address[] memory aUsers = new address[](2);
		uint256[] memory aAmounts = new uint256[](2);
		aUsers[0] = user1;
		aUsers[1] = user2;
		aAmounts[0] = 100e18;
		aAmounts[1] = 50e18;

		assertEq(indiv1.getClaimable(user1), 0e18, "User1 nothing to claim initially");
		assertEq(indiv1.getClaimable(user2), 0e18, "User2 nothing to claim initially");
		assertEq(indiv1.getClaimable(user3), 0e18, "User3 nothing to claim initially");

		vm.expectEmit(true, true, true, true);
		emit AddedUsers(aUsers, aAmounts);

		indiv1.addUsers(aUsers, aAmounts);

		assertEq(indiv1.getClaimable(user1), 100e18, "User1 has 100 to claim");
		assertEq(indiv1.getClaimable(user2), 50e18, "User2 has 50 to claim");
		assertEq(indiv1.getClaimable(user3), 0e18, "User3 has nothing to claim");
	}

	function _addClaimables() internal {
		address[] memory aUsers = new address[](2);
		uint256[] memory aAmounts = new uint256[](2);
		aUsers[0] = user1;
		aUsers[1] = user2;
		aAmounts[0] = 100e18;
		aAmounts[1] = 50e18;

		indiv1.addUsers(aUsers, aAmounts);
	}

	function test_closeAirdrop_ExpectEmit_ClosedAirdrop() public {
		// Revert if not owner
		vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1));
		vm.prank(user1);
		indiv1.closeAirdrop(true);

		// Initially false
		assertEq(indiv1.closed(), false, "Initially open");

		// Emits and sets to true
		vm.expectEmit(true, true, true, true);
		emit ClosedAirdrop(true);
		indiv1.closeAirdrop(true);
		assertEq(indiv1.closed(), true, "Set to true");

		// Emits and sets to false
		vm.expectEmit(true, true, true, true);
		emit ClosedAirdrop(false);
		indiv1.closeAirdrop(false);
		assertEq(indiv1.closed(), false, "Reset back to false");
	}

	function test_claim_Reversions() public {
		_giveVoucher(treasury, 10000e18);

		vm.prank(treasury);
		VOUCHER.approve(address(indiv1), UINT256_MAX);

		_addClaimables();

		// Trying to claim for another user
		vm.expectRevert(Invalid.selector);
		vm.prank(user1);
		indiv1.claim(user2, 50e18);

		// Closed -> revert Closed()
		indiv1.closeAirdrop(true);
		vm.expectRevert(Closed.selector);
		vm.prank(user1);
		indiv1.claim(user1, 100e18);

		indiv1.closeAirdrop(false);

		// userAmount is 0 -> NothingToClaim()
		vm.expectRevert(NothingToClaim.selector);
		vm.prank(user3);
		indiv1.claim(user3, 0e18);

		// userAmount = userClaimed -> AlreadyClaimed()
		vm.prank(user2);
		indiv1.claim(user2, 50e18);

		vm.expectRevert(AlreadyClaimed.selector);

		vm.prank(user2);
		indiv1.claim(user2, 50e18);

		// amount != claimable -> Invalid()
		vm.expectRevert(Invalid.selector);
		vm.prank(user1);
		indiv1.claim(user1, 50e18);
	}

	function test_claim_ExpectEmit_Claimed() public {
		_giveVoucher(treasury, 10000e18);

		vm.prank(treasury);
		VOUCHER.approve(address(indiv1), UINT256_MAX);

		_addClaimables();

		assertEq(indiv1.getClaimable(user1), 100e18, "User1 can claim 100e18");

		_expectTokenTransfer(VOUCHER, address(treasury), user1, 100e18);

		vm.expectEmit(true, true, true, true);
		emit Claimed(user1, 100e18);

		vm.prank(user1);
		indiv1.claim(user1, 100e18);

		assertEq(indiv1.userAmount(user1), 100e18, "User1 allocated 100");
		assertEq(indiv1.userClaimed(user1), 100e18, "User1 claimed 100");
		assertEq(indiv1.getClaimable(user1), 0e18, "User1 has nothing left to claim");
	}
}
