// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ChainJsonUtils } from "./ChainJsonUtils.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { IWETH, WETH9 } from "../WETH9.sol";
import { Auctioneer } from "../Auctioneer.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { GOToken } from "../GOToken.sol";
import { VOUCHERToken } from "../VOUCHERToken.sol";

contract GBScriptUtils is Script, ChainJsonUtils {
	using SafeERC20 for IERC20;

	// Ecosystem contracts
	Auctioneer auctioneer;
	AuctioneerFarm auctioneerFarm;
	GOToken GO;
	VOUCHERToken VOUCHER;
	IERC20 USD;
	IWETH WETH;

	// Config
	bool isBlast;
	bool isAnvil;

	// Default bidding values for a 18 decimal USD
	uint256 bidCost = 0.6e18;
	uint256 bidIncrement = 0.01e18;
	uint256 startingBid = 1e18;

	// Config values
	uint256 privateAuctionRequirement = 20e18;
	uint256 earlyHarvestTax = 5000;
	uint256 emissionTaxDuration = 30 days;
	address treasury;
	uint256 treasurySplit = 2000;

	modifier startBroadcast() {
		string memory mnemonic = vm.envString("MNEMONIC");
		(address deployer, ) = deriveRememberKey(mnemonic, 0);
		vm.startBroadcast(deployer);
		_;
		vm.stopBroadcast();
	}

	modifier loadContracts() {
		if (bytes(chainName).length == 0) revert ChainNameNotSet();
		auctioneer = Auctioneer(payable(readAddress(contractPath("auctioneer"))));
		auctioneerFarm = AuctioneerFarm(readAddress(contractPath("auctioneerFarm")));
		GO = GOToken(readAddress(contractPath("GO")));
		VOUCHER = VOUCHERToken(readAddress(contractPath("VOUCHER")));
		USD = IERC20(readAddress(contractPath("USD")));
		WETH = IWETH(readAddress(contractPath("WETH")));
		_;
	}

	modifier loadConfigValues() {
		if (bytes(chainName).length == 0) revert ChainNameNotSet();

		isBlast = readBool(configPath("isBlast"));
		isAnvil = readBool(configPath("isAnvil"));

		bidCost = readUint(auctioneerConfigPath("bidCost"));
		startingBid = readUint(auctioneerConfigPath("startingBid"));
		privateAuctionRequirement = readUint(auctioneerConfigPath("privateAuctionRequirement"));
		earlyHarvestTax = readUint(auctioneerConfigPath("earlyHarvestTax"));
		emissionTaxDuration = readUint(auctioneerConfigPath("emissionTaxDurationDays")) * 1 days;
		treasury = readAddress(auctioneerConfigPath("treasury"));
		treasurySplit = readUint(auctioneerConfigPath("treasurySplit"));
		_;
	}
}
