// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "../Auctioneer.sol";
import "../IAuctioneer.sol";
import { GOToken } from "../GOToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { IWETH, WETH9 } from "../WETH9.sol";

abstract contract AuctioneerHelper {
	// DATA

	address public deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
	address public sender = 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496;

	address public presale = address(30);

	address public liquidity = address(40);

	address public treasury = address(50);
	address public treasury2 = address(51);

	address public user1 = address(100);
	address public user2 = address(101);
	address public user3 = address(102);
	address public user4 = address(103);

	Auctioneer public auctioneer;
	AuctioneerFarm public farm;
	BasicERC20 public USD;
	IWETH public WETH;
	address public ETH_ADDR = address(0);
	IERC20 public GO;

	// SETUP

	function setUp() public virtual {
		USD = new BasicERC20("USD", "USD");
		WETH = IWETH(address(new WETH9()));
		GO = new GOToken(deployer);

		auctioneer = new Auctioneer(USD, GO, WETH, 1e18, 1e16, 1e18, 20e18);
	}

	// EVENTS

	error OwnableUnauthorizedAccount(address account);
	error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
	error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
}
