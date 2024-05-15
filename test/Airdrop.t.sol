// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AirdropTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();
		_distributeGO();
	}

	// Its ugly, but its done
	event Closed(bool _closed);
	event TokensClaimed(address indexed _claimer, address indexed _to, uint256 _amount);
	error ClaimZero();
	error ClaimExceeded();
	error AirdropClosed();
	error LengthMismatch();

	/*
  [x] Voucher address correct
  [x] Owner address correct
  [x] Voucher owner address correct

  [x] Adding user airdrops works
    [x] Revert on length mismatch

  [x] Expiration timestamp works

  [x] Airdrop can be closed
    [x] Closed airdrop not purchaseable
    

  [x] Claimable amounts return correctly
  [x] Can only claim once
  [x] Claim < Available or ClaimExceeded
  [x] Claim > 0 or ClaimZero

  [x] Transfers claimed VOUCHER correctly


  */

	function _airdropUsers() internal {
		address[] memory addresses = new address[](2);
		addresses[0] = user1;
		addresses[1] = user2;

		uint256[] memory amounts = new uint256[](2);
		amounts[0] = 10e18;
		amounts[1] = 5e18;

		airdrop.addUserAirdrops(addresses, amounts);
	}

	function test_airdrop_ValidInitialState() public {
		assertEq(airdrop.voucher(), address(VOUCHER), "Voucher address correct");
		assertEq(airdrop.owner(), sender, "Owner is sender");
		assertEq(airdrop.voucherOwner(), treasury, "Treasury holds voucher");
	}

	function test_airdrop_ExpectEmit_Closed() public {
		vm.expectEmit(true, true, true, true);
		emit Closed(true);

		airdrop.close(true);

		vm.expectEmit(true, true, true, true);
		emit Closed(false);

		airdrop.close(false);
	}

	function test_airdrop_Expect_UsersAdded() public {
		assertEq(airdrop.claimable(user1).amount, 0, "User 1 has nothing to claim");
		assertEq(airdrop.claimable(user1).claimed, 0, "User 1 has not claimed anything");
		assertEq(airdrop.claimable(user2).amount, 0, "User 2 has nothing to claim");
		assertEq(airdrop.claimable(user2).claimed, 0, "User 2 has not claimed anything");

		_airdropUsers();

		assertEq(airdrop.claimable(user1).amount, 10e18, "User 1 has 10e18 to claim");
		assertEq(airdrop.claimable(user1).claimed, 0, "User 1 has still not claimed anything");
		assertEq(airdrop.claimable(user2).amount, 5e18, "User 2 has 5e18 to claim");
		assertEq(airdrop.claimable(user2).claimed, 0, "User 2 has still not claimed anything");
	}

	function test_airdrop_ExpectRevert_LengthMismatch() public {
		address[] memory addresses = new address[](2);
		addresses[0] = user1;
		addresses[1] = user2;

		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 10e18;

		vm.expectRevert(LengthMismatch.selector);

		airdrop.addUserAirdrops(addresses, amounts);
	}

	function test_airdrop_ExpectEmit_TokensClaimed() public {
		_airdropUsers();

		_expectTokenTransfer(VOUCHER, treasury, user1, 5e18);

		vm.expectEmit(true, true, true, true);
		emit TokensClaimed(user1, user1, 5e18);

		vm.prank(user1);
		airdrop.claim(5e18, user1);

		assertEq(airdrop.claimable(user1).amount, 5e18, "User 1 has 5e18 to claim");
		assertEq(airdrop.claimable(user1).claimed, 5e18, "User 1 has claimed 5e18");

		_expectTokenTransfer(VOUCHER, treasury, user2, 5e18);

		vm.expectEmit(true, true, true, true);
		emit TokensClaimed(user1, user2, 5e18);

		vm.prank(user1);
		airdrop.claim(5e18, user2);

		assertEq(airdrop.claimable(user1).amount, 0, "User 1 has 0 to claim");
		assertEq(airdrop.claimable(user1).claimed, 10e18, "User 1 has claimed 10e18");
	}

	function test_airdrop_expectRevert_ClaimZero() public {
		vm.expectRevert(ClaimZero.selector);

		vm.prank(user1);
		airdrop.claim(0, user1);
	}

	function test_airdrop_expectRevert_ClaimExceeded() public {
		_airdropUsers();

		vm.expectRevert(ClaimExceeded.selector);

		vm.prank(user1);
		airdrop.claim(10.01e18, user1);
	}

	function test_airdrop_expectRevert_AirdropClosed_ByAdmin() public {
		_airdropUsers();

		airdrop.close(true);

		vm.expectRevert(AirdropClosed.selector);

		vm.prank(user1);
		airdrop.claim(5e18, user1);

		airdrop.close(false);

		vm.expectEmit(true, true, true, true);
		emit TokensClaimed(user1, user1, 5e18);

		vm.prank(user1);
		airdrop.claim(5e18, user1);
	}

	function test_airdrop_expectRevert_AirdropClosed_ByExpirationTimestamp() public {
		_airdropUsers();

		vm.expectEmit(true, true, true, true);
		emit TokensClaimed(user1, user1, 5e18);

		vm.prank(user1);
		airdrop.claim(5e18, user1);

		vm.warp(airdrop.expirationTimestamp() + 1);

		vm.expectRevert(AirdropClosed.selector);

		vm.prank(user1);
		airdrop.claim(5e18, user1);
	}
}
