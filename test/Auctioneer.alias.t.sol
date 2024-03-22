// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerHelper } from "./Auctioneer.base.t.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AuctioneerAliasTest is AuctioneerHelper {
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

		// Give WETH to treasury
		vm.deal(treasury, 10e18);

		// Treasury deposit for WETH
		vm.prank(treasury);
		WETH.deposit{ value: 5e18 }();

		// Approve WETH for auctioneer
		vm.prank(treasury);
		IERC20(address(WETH)).approve(address(auctioneer), type(uint256).max);
	}

	function test_setAlias_RevertWhen_InvalidAlias() public {
		// Length < 3
		vm.expectRevert(InvalidAlias.selector);
		auctioneer.setAlias("AA");

		// Length > 9
		vm.expectRevert(InvalidAlias.selector);
		auctioneer.setAlias("AAAAAAAAAA");
	}

	function test_setAlias_ExpectEmit_UpdatedAlias() public {
		vm.expectEmit(true, true, true, true);
		emit UpdatedAlias(sender, "TEST");

		auctioneer.setAlias("TEST");
	}

	function test_setAlias_RevertWhen_AliasTaken() public {
		auctioneer.setAlias("XXXX");

		vm.expectRevert(AliasTaken.selector);
		vm.prank(user1);
		auctioneer.setAlias("XXXX");
	}

	function test_setAlias_ClearPreviouslyUsedAlias() public {
		auctioneer.setAlias("XXXX");

		vm.expectRevert(AliasTaken.selector);
		vm.prank(user1);
		auctioneer.setAlias("XXXX");

		assertEq(auctioneer.aliasUser("XXXX"), sender, "Alias should point to correct user");
		assertEq(auctioneer.userAlias(sender), "XXXX", "User should point to correct alias");

		auctioneer.setAlias("YYYY");

		assertEq(auctioneer.aliasUser("XXXX"), address(0), "Alias should point to address(0)");
		assertEq(auctioneer.userAlias(sender), "YYYY", "User should point to new alias");

		vm.expectEmit(true, true, true, true);
		emit UpdatedAlias(user1, "XXXX");
		vm.prank(user1);
		auctioneer.setAlias("XXXX");
	}
}
