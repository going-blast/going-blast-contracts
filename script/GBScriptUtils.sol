// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ChainJsonUtils } from "./ChainJsonUtils.sol";
import { IWETH } from "../src/WETH9.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { GoToken } from "../src/GoToken.sol";
import { VoucherToken } from "../src/VoucherToken.sol";

contract GBScriptUtils is Script, ChainJsonUtils {
	using SafeERC20 for IERC20;

	// Ecosystem contracts
	Auctioneer public auctioneer;
	AuctioneerFarm public auctioneerFarm;
	GoToken public GO;
	VoucherToken public VOUCHER;
	IERC20 public USD;
	IWETH public WETH;

	// Config
	bool public isBlast;
	bool public isAnvil;

	// Default bidding values for a 18 decimal USD
	uint256 public bidCost = 0.6e18;
	uint256 public bidIncrement = 0.01e18;
	uint256 public startingBid = 1e18;

	// Config values
	uint256 public privateAuctionRequirement = 20e18;
	uint256 public earlyHarvestTax = 5000;
	uint256 public emissionTaxDuration = 30 days;
	address public treasury;
	uint256 public treasurySplit = 2000;

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
		GO = GoToken(readAddress(contractPath("GO")));
		VOUCHER = VoucherToken(readAddress(contractPath("VOUCHER")));
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
