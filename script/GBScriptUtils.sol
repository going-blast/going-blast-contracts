// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ChainJsonUtils } from "./ChainJsonUtils.sol";
import { IWETH } from "../src/WETH9.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { AuctioneerAuction } from "../src/AuctioneerAuction.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { AuctioneerEmissions } from "../src/AuctioneerEmissions.sol";
import { GoToken } from "../src/GoToken.sol";
import { VoucherToken } from "../src/VoucherToken.sol";
import { GoingBlastAirdrop } from "../src/GoingBlastAirdrop.sol";

contract GBScriptUtils is Script, ChainJsonUtils {
	using SafeERC20 for IERC20;

	// Ecosystem contracts
	Auctioneer public auctioneer;
	AuctioneerAuction public auctioneerAuction;
	AuctioneerEmissions public auctioneerEmissions;
	AuctioneerFarm public auctioneerFarm;
	GoingBlastAirdrop public airdrop;
	GoToken public GO;
	VoucherToken public VOUCHER;
	IWETH public WETH;

	// Config
	bool public isBlast;
	bool public isAnvil;

	// Default bidding values for a 18 decimal ETH
	uint256 public bidCost = 0.00035e18;
	uint256 public startingBid = 0.00035e18;
	uint256 public bidIncrement = 0.0000035e18;

	// Config values
	uint256 public privateAuctionRequirement = 250e18;
	uint256 public earlyHarvestTax = 5000;
	uint256 public emissionTaxDuration = 30 days;
	uint256 public teamTreasurySplit = 2000;

	// Addresses
	address public multisig;
	address public treasury;
	address public teamTreasury;

	modifier broadcast() {
		string memory mnemonic = vm.envString("MNEMONIC");
		(address deployer, ) = deriveRememberKey(mnemonic, 0);
		vm.startBroadcast(deployer);
		_;
		vm.stopBroadcast();
	}
	modifier broadcastTreasury() {
		string memory mnemonic = vm.envString("MNEMONIC");
		(address _treasury, ) = deriveRememberKey(mnemonic, 1);
		vm.startBroadcast(_treasury);
		_;
		vm.stopBroadcast();
	}

	modifier loadContracts() {
		if (bytes(chainName).length == 0) revert ChainNameNotSet();

		auctioneer = Auctioneer(payable(readAddress(contractPath("Auctioneer"))));
		auctioneerAuction = AuctioneerAuction(payable(readAddress(contractPath("AuctioneerAuction"))));
		auctioneerEmissions = AuctioneerEmissions(readAddress(contractPath("AuctioneerEmissions")));
		auctioneerFarm = AuctioneerFarm(readAddress(contractPath("AuctioneerFarm")));
		airdrop = GoingBlastAirdrop(readAddress(contractPath("GoingBlastAirdrop")));
		GO = GoToken(readAddress(contractPath("GO")));
		VOUCHER = VoucherToken(readAddress(contractPath("VOUCHER")));
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
		teamTreasurySplit = readUint(auctioneerConfigPath("teamTreasurySplit"));

		multisig = readAddress(auctioneerConfigPath("multisig"));
		treasury = readAddress(auctioneerConfigPath("treasury"));
		teamTreasury = readAddress(auctioneerConfigPath("teamTreasury"));
		_;
	}
}
