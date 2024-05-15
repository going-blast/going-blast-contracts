// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerFundsTest is AuctioneerHelper {
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
	}

	function testFail_addFunds_RevertWhen_InsufficientBalance() public {
		vm.prank(user1);
		auctioneerUser.addFunds{ value: 100000e18 }();
	}

	function test_addFunds_ExpectEmit_AddedFunds() public {
		vm.expectEmit(true, true, true, true);
		emit AddedFunds(user1, 10e18);

		_addUserFunds(user1, 10e18);
	}

	function test_addFunds_Success() public {
		vm.deal(user1, 10e18);

		_prepExpectETHTransfer(0, user1, address(auctioneer));

		_addUserFundsNoDeal(user1, 10e18);

		_expectETHTransfer(0, user1, address(auctioneer), 10e18);
		assertEq(auctioneerUser.userFunds(user1), 10e18, "User added funds marked in auctioneer");
	}

	function test_withdrawFunds_RevertWhen_InsufficientDeposited() public {
		vm.expectRevert(BadWithdrawal.selector);

		vm.prank(user1);
		auctioneerUser.withdrawFunds(100000e18);
	}

	function test_withdrawFunds_ExpectEmit_WithdrewFunds() public {
		_addUserFunds(user1, 20e18);

		vm.expectEmit(true, true, true, true);
		emit WithdrewFunds(user1, 10e18);

		vm.prank(user1);
		auctioneerUser.withdrawFunds(10e18);
	}

	function test_withdrawFunds_Success() public {
		_addUserFunds(user1, 15e18);

		_prepExpectETHTransfer(0, address(auctioneer), user1);

		vm.prank(user1);
		auctioneerUser.withdrawFunds(10e18);

		assertEq(auctioneerUser.userFunds(user1), 15e18 - 10e18, "User withdrawn funds marked in auctioneer");
		_expectETHTransfer(0, address(auctioneer), user1, 10e18);
	}
}
