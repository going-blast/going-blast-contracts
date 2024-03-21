// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH } from "../WETH9.sol";
import { Auctioneer } from "../Auctioneer.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { GOToken } from "../GOToken.sol";
import { VOUCHERToken } from "../VOUCHERToken.sol";

contract GBDeployScript is Script {
	using SafeERC20 for IERC20;

	// Ecosystem contracts
	Auctioneer auctioneer;
	AuctioneerFarm auctioneerFarm;
	GOToken GO;
	VOUCHERToken VOUCHER;
	IERC20 USD;
	IWETH WETH;

	// Default bidding values for a 18 decimal USD
	uint256 bidCost = 0.6e18;
	uint256 bidIncrement = 0.01e18;
	uint256 startingBid = 1e18;

	// Config values
	uint256 privateRequirement = 20e18;
	uint256 earlyHarvestTax = 5000;
	uint256 emissionTaxDuration = 30 days;
	address treasury;
	uint256 treasurySplit = 2000;

	error AlreadyInitialized();

	modifier startBroadcast() {
		uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
		vm.startBroadcast(deployerPrivateKey);
		_;
		vm.stopBroadcast();
	}

	modifier loadContracts() {
		auctioneer = Auctioneer(vm.envAddress("AUCTIONEER_ADDRESS"));
		auctioneerFarm = Auctioneer(vm.envAddress("AUCTIONEER_FARM_ADDRESS"));
		GO = GOToken(vm.envAddress("GO_TOKEN_ADDRESS"));
		VOUCHER = VOUCHERToken(vm.envAddress("VOUCHER_TOKEN_ADDRESS"));
		USD = IERC20(vm.envAddress("USD_ADDRESS"));
		WETH = IWETH(vm.envAddress("WETH_ADDRESS"));
	}

	modifier loadValues() {
		bidCost = vm.envUint("BID_COST");
		startingBid = vm.envUint("STARTING_BID");
		privateRequirement = vm.envUint("PRIVATE_REQUIREMENT");
		earlyHarvestTax = vm.envUint("EARLY_HARVEST_TAX");
		emissionTaxDuration = vm.envUint("EMISSION_TAX_DURATION");
		treasury = vm.envAddress("TREASURY_ADDRESS");
		treasurySplit = vm.envUint("TREASURY_SPLIT");
	}

	function deploy() external startBroadcast loadValues {
		USD = IERC20(vm.envAddress("USD_ADDRESS"));
		WETH = IWETH(vm.envAddress("WETH_ADDRESS"));

		GO = new GOToken();
		console.log("DEPLOYED GO TOKEN :: %s", address(GO));

		VOUCHER = new VOUCHERToken();
		console.log("DEPLOYED VOUCHER TOKEN :: %s", address(VOUCHER));

		auctioneer = new Auctioneer(USD, GO, VOUCHER, WETH, bidCost, bidIncrement, startingBid, privateRequirement);
		console.log("DEPLOYED AUCTIONEER :: %s", address(auctioneer));

		auctioneerFarm = new AuctioneerFarm(USD, GO, VOUCHER);
		console.log("DEPLOYED AUCTIONEER FARM :: %s", address(auctioneerFARM));
		// TODO: write these addresses to a json file
	}

	function initializeAuctioneer() external startBroadcast loadContracts {
		if (auctioneer.initialized()) revert AlreadyInitialized();

		uint256 proofOfBidEmissions = (10000000e18 * 6000) / 10000;
		GO.safeTransfer(address(auctioneerFarm), proofOfBidEmissions);

		uint256 unlockTimestamp = block.timestamp; // TODO this needs to be updated to a correct value
		auctioneer.initialize(unlockTimestamp);
	}

	function createDailyAuctions(uint256 day) external startBroadcast loadContracts {
		// TODO: read daily auctions from JSON, create them
		// TODO: mark the daily auctions as created in the JSON file
	}
	function cancelAuction(uint256 lot) external startBroadcast loadContracts {
		auctioneer.cancelAuction(lot, false);
	}

	function syncConfigValues() external startBroadcast loadContracts loadValues {
		if (bidCost != auctioneer.bidCost()) {
			auctioneer.updateBidCost(bidCost);
		}

		if (startingBid != auctioneer.startingBid()) {
			auctioneer.updateStartingBid(startingBid);
		}

		if (privateAuctionRequirement != auctioneer.privateAuctionRequirement()) {
			auctioneer.updatePrivateAuctionRequirement(privateAuctionRequirement);
		}

		if (earlyHarvestTax != auctioneer.earlyHarvestTax()) {
			auctioneer.updateEarlyHarvestTax(earlyHarvestTax);
		}

		if (emissionTaxDuration != auctioneer.emissionTaxDuration()) {
			auctioneer.updateEmissionTaxDuration(emissionTaxDuration);
		}

		if (treasurySplit != auctioneer.treasurySplit()) {
			auctioneer.setTreasurySplit(treasurySplit);
		}

		if (treasury != auctioneer.treasury()) {
			auctioneer.setTreasury(treasury);
		}
	}
}
