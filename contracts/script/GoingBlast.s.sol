// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBScriptUtils } from "./GBScriptUtils.sol";
import { BasicERC20 } from "../BasicERC20.sol";
import { IWETH, WETH9 } from "../WETH9.sol";
import { Auctioneer } from "../Auctioneer.sol";
import { AuctioneerFarm } from "../AuctioneerFarm.sol";
import { GOToken } from "../GOToken.sol";
import { VOUCHERToken } from "../VOUCHERToken.sol";

contract GBDeploy is GBScriptUtils {
	function run() external startBroadcast loadChain loadConfigValues {
		if (isAnvil) {
			USD = IERC20(address(new BasicERC20("USD", "USD")));
			writeAddress(contractPath("USD"), address(USD));
			WETH = IWETH(address(new WETH9()));
			writeAddress(contractPath("WETH"), address(WETH));
		} else {
			USD = IERC20(readAddress(contractPath("USD")));
			WETH = IWETH(readAddress(contractPath("WETH")));
		}

		GO = new GOToken();
		writeAddress(contractPath("GO"), address(GO));

		VOUCHER = new VOUCHERToken();
		writeAddress(contractPath("VOUCHER"), address(VOUCHER));

		auctioneer = new Auctioneer(USD, GO, VOUCHER, WETH, bidCost, bidIncrement, startingBid, privateAuctionRequirement);
		writeAddress(contractPath("auctioneer"), address(auctioneer));

		auctioneerFarm = new AuctioneerFarm(USD, GO, VOUCHER);
		writeAddress(contractPath("auctioneerFarm"), address(auctioneerFarm));
	}
}

contract GBSetTreasuryFromMnemonic is GBScriptUtils {
	function run() external loadChain {
		string memory mnemonic = vm.envString("MNEMONIC");
		(treasury, ) = deriveRememberKey(mnemonic, 0);
		writeAddress(auctioneerConfigPath("treasury"), treasury);
	}
}

contract GBInitializeAuctioneer is GBScriptUtils {
	using SafeERC20 for IERC20;
	error AlreadyInitialized();

	function run() external startBroadcast loadChain loadContracts {
		if (auctioneer.initialized()) revert AlreadyInitialized();

		uint256 proofOfBidEmissions = (10000000e18 * 6000) / 10000;
		IERC20(GO).safeTransfer(address(auctioneer), proofOfBidEmissions);

		uint256 unlockTimestamp = block.timestamp; // TODO this needs to be updated to a correct value
		auctioneer.initialize(unlockTimestamp);
	}
}

contract GBCreateDailyAuctions is GBScriptUtils {
	function run(uint256 day) external startBroadcast loadChain loadContracts {
		// TODO: read daily auctions from JSON, create them
		// TODO: mark the daily auctions as created in the JSON file
	}
}

contract GBCancelAuction is GBScriptUtils {
	function run(uint256 lot) external startBroadcast loadChain loadContracts {
		auctioneer.cancelAuction(lot, false);
	}
}

contract GBSyncConfigValues is GBScriptUtils {
	function run() external startBroadcast loadChain loadContracts loadConfigValues {
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

		console.log("Update Treasury:", treasury, auctioneer.treasury());
		if (treasury != auctioneer.treasury()) {
			auctioneer.setTreasury(treasury);
		}
	}
}
