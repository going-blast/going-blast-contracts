// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { Auctioneer } from "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { WETH9 } from "../WETH9.sol";

contract AuctioneerFundsTest is AuctioneerHelper {
	using SafeERC20 for IERC20;

	function setUp() public override {
		super.setUp();

		farm = new AuctioneerFarm(USD, GO, VOUCHER);
		auctioneer.setTreasury(treasury);

		// Distribute GO
		GO.safeTransfer(address(auctioneer), (GO.totalSupply() * 6000) / 10000);
		GO.safeTransfer(presale, (GO.totalSupply() * 2000) / 10000);
		GO.safeTransfer(treasury, (GO.totalSupply() * 1000) / 10000);
		GO.safeTransfer(liquidity, (GO.totalSupply() * 500) / 10000);
		GO.safeTransfer(address(farm), (GO.totalSupply() * 500) / 10000);

		// Initialize after receiving GO token
		auctioneer.initialize(_getNextDay2PMTimestamp());

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);

		// Give usd to users
		USD.mint(user1, 1000e18);
		USD.mint(user2, 1000e18);
		USD.mint(user3, 1000e18);
		USD.mint(user4, 1000e18);

		// Users approve auctioneer
		vm.prank(user1);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user2);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user3);
		USD.approve(address(auctioneer), 1000e18);
		vm.prank(user4);
		USD.approve(address(auctioneer), 1000e18);

		// Create auction
		AuctionParams[] memory params = new AuctionParams[](1);
		params[0] = _getBaseSingleAuctionParams();
		auctioneer.createDailyAuctions(params);
	}

	function test_addFunds_RevertWhen_InsufficientBalance() public {
		vm.expectRevert(BadDeposit.selector);

		vm.prank(user1);
		auctioneer.addFunds(100000e18);
	}

	function test_addFunds_RevertWhen_InsufficientAllowance() public {
		vm.prank(user1);
		IERC20(USD).approve(address(auctioneer), 0);

		vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(auctioneer), 0, 10e18));

		vm.prank(user1);
		auctioneer.addFunds(10e18);
	}

	function test_addFunds_ExpectEmit_AddedFunds() public {
		vm.expectEmit(true, true, true, true);
		emit AddedFunds(user1, 10e18);

		vm.prank(user1);
		auctioneer.addFunds(10e18);
	}

	function test_addFunds_Success() public {
		uint256 userUSDInit = USD.balanceOf(user1);

		vm.prank(user1);
		auctioneer.addFunds(10e18);

		assertEq(auctioneer.userFunds(user1), 10e18, "User added funds marked in auctioneer");
		assertEq(USD.balanceOf(address(auctioneer)), 10e18, "Auctioneer received USD");
		assertEq(USD.balanceOf(user1), userUSDInit - 10e18, "User sent USD");
	}

	function test_withdrawFunds_RevertWhen_InsufficientDeposited() public {
		vm.expectRevert(BadWithdrawal.selector);

		vm.prank(user1);
		auctioneer.withdrawFunds(100000e18);
	}

	function test_withdrawFunds_ExpectEmit_WithdrewFunds() public {
		vm.prank(user1);
		auctioneer.addFunds(20e18);

		vm.expectEmit(true, true, true, true);
		emit WithdrewFunds(user1, 10e18);

		vm.prank(user1);
		auctioneer.withdrawFunds(10e18);
	}

	function test_withdrawFunds_Success() public {
		vm.prank(user1);
		auctioneer.addFunds(15e18);

		uint256 auctioneerUSDInit = USD.balanceOf(address(auctioneer));
		uint256 userUSDInit = USD.balanceOf(user1);

		vm.prank(user1);
		auctioneer.withdrawFunds(10e18);

		assertEq(auctioneer.userFunds(user1), 15e18 - 10e18, "User withdrawn funds marked in auctioneer");
		assertEq(USD.balanceOf(address(auctioneer)), auctioneerUSDInit - 10e18, "Auctioneer sent USD");
		assertEq(USD.balanceOf(user1), userUSDInit + 10e18, "User received USD");
	}
}
