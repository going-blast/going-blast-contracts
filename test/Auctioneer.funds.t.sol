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

	function test_addFunds_RevertWhen_InsufficientBalance() public {
		vm.expectRevert(BadDeposit.selector);

		vm.prank(user1);
		auctioneerUser.addFunds(100000e18);
	}

	function test_addFunds_RevertWhen_InsufficientAllowance() public {
		vm.prank(user1);
		IERC20(USD).approve(address(auctioneerUser), 0);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneerUser), 0, 10e18));

		vm.prank(user1);
		auctioneerUser.addFunds(10e18);
	}

	function test_addFunds_ExpectEmit_AddedFunds() public {
		vm.expectEmit(true, true, true, true);
		emit AddedFunds(user1, 10e18);

		vm.prank(user1);
		auctioneerUser.addFunds(10e18);
	}

	function test_addFunds_Success() public {
		uint256 userUSDInit = USD.balanceOf(user1);

		vm.prank(user1);
		auctioneerUser.addFunds(10e18);

		assertEq(auctioneerUser.userFunds(user1), 10e18, "User added funds marked in auctioneer");
		assertEq(USD.balanceOf(address(auctioneer)), 10e18, "AuctionManager received USD");
		assertEq(USD.balanceOf(user1), userUSDInit - 10e18, "User sent USD");
	}

	function test_withdrawFunds_RevertWhen_InsufficientDeposited() public {
		vm.expectRevert(BadWithdrawal.selector);

		vm.prank(user1);
		auctioneerUser.withdrawFunds(100000e18);
	}

	function test_withdrawFunds_ExpectEmit_WithdrewFunds() public {
		vm.prank(user1);
		auctioneerUser.addFunds(20e18);

		vm.expectEmit(true, true, true, true);
		emit WithdrewFunds(user1, 10e18);

		vm.prank(user1);
		auctioneerUser.withdrawFunds(10e18);
	}

	function test_withdrawFunds_Success() public {
		vm.prank(user1);
		auctioneerUser.addFunds(15e18);

		uint256 auctioneerUSDInit = USD.balanceOf(address(auctioneer));
		uint256 userUSDInit = USD.balanceOf(user1);

		vm.prank(user1);
		auctioneerUser.withdrawFunds(10e18);

		assertEq(auctioneerUser.userFunds(user1), 15e18 - 10e18, "User withdrawn funds marked in auctioneer");
		assertEq(USD.balanceOf(address(auctioneer)), auctioneerUSDInit - 10e18, "AuctionManager sent USD");
		assertEq(USD.balanceOf(user1), userUSDInit + 10e18, "User received USD");
	}
}
