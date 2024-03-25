// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable no-console

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBScriptUtils } from "./GBScriptUtils.sol";
import { BasicERC20 } from "../src/BasicERC20.sol";
import { IWETH, WETH9 } from "../src/WETH9.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { AuctioneerUser } from "../src/AuctioneerUser.sol";
import { AuctioneerEmissions } from "../src/AuctioneerEmissions.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { GoToken } from "../src/GoToken.sol";
import { VoucherToken } from "../src/VoucherToken.sol";
import { IERC20Rebasing } from "../src/BlastYield.sol";
import { GBMath } from "../src/AuctionUtils.sol";

contract GBScripts is GBScriptUtils {
	using SafeERC20 for IERC20;
	using GBMath for uint256;
	error AlreadyInitialized();
	error NotBlastChain();

	function fullDeploy() public broadcast loadChain loadConfigValues {
		_deployCore();
		_updateTreasury();
		_initializeAuctioneerEmissions();
	}

	function deployCore() public broadcast loadChain loadConfigValues {
		_deployCore();
	}

	function updateTreasury() public broadcast loadChain loadContracts {
		_updateTreasury();
	}

	function initializeAuctioneerEmissions() public broadcast loadChain loadContracts {
		_initializeAuctioneerEmissions();
	}

	function _deployCore() internal {
		if (isAnvil) {
			USD = IERC20(address(new BasicERC20("USD", "USD")));
			writeAddress(contractPath("USD"), address(USD));
			WETH = IWETH(address(new WETH9()));
			writeAddress(contractPath("WETH"), address(WETH));
		} else {
			USD = IERC20(readAddress(contractPath("USD")));
			WETH = IWETH(readAddress(contractPath("WETH")));
		}

		GO = new GoToken();
		writeAddress(contractPath("GO"), address(GO));

		VOUCHER = new VoucherToken();
		writeAddress(contractPath("VOUCHER"), address(VOUCHER));

		auctioneer = new Auctioneer(GO, VOUCHER, USD, WETH, bidCost, bidIncrement, startingBid, privateAuctionRequirement);
		writeAddress(contractPath("auctioneer"), address(auctioneer));

		auctioneerUser = new AuctioneerUser(USD);
		writeAddress(contractPath("auctioneerUser"), address(auctioneerUser));

		auctioneerEmissions = new AuctioneerEmissions(GO);
		writeAddress(contractPath("auctioneerEmissions"), address(auctioneerEmissions));

		auctioneer.link(address(auctioneerUser), address(auctioneerEmissions));

		auctioneerFarm = new AuctioneerFarm(USD, GO, VOUCHER);
		writeAddress(contractPath("auctioneerFarm"), address(auctioneerFarm));

		auctioneer.updateFarm(address(auctioneerFarm));

		if (isBlast) {
			auctioneer.initializeBlast();
			auctioneerFarm.initializeBlast(address(WETH));
		}
	}

	function _updateTreasury() internal {
		string memory mnemonic = vm.envString("MNEMONIC");
		(treasury, ) = deriveRememberKey(mnemonic, 1);

		auctioneer.updateTreasury(treasury);
		writeAddress(auctioneerConfigPath("treasury"), treasury);
	}

	function _initializeAuctioneerEmissions() internal {
		if (auctioneerEmissions.emissionsInitialized()) revert AlreadyInitialized();

		uint256 proofOfBidEmissions = uint256(1000000e18).scaleByBP(6000);
		IERC20(GO).safeTransfer(address(auctioneerEmissions), proofOfBidEmissions);

		uint256 unlockTimestamp = block.timestamp; // TODO: Maybe consider changing this, not really that important though
		auctioneerEmissions.initializeEmissions(unlockTimestamp);
	}

	function createDailyAuctions(uint256 day) public broadcast loadChain loadContracts {
		// TODO: read daily auctions from JSON, create them
		// TODO: mark the daily auctions as created in the JSON file
	}

	function cancelAuction(uint256 lot) public broadcast loadChain loadContracts {
		auctioneer.cancelAuction(lot, false);
	}

	function syncConfigValues() public broadcast loadChain loadContracts loadConfigValues {
		console.log(". sync bidCost");
		if (bidCost != auctioneer.bidCost()) {
			console.log("  . bidCost updated %s --> %s", auctioneer.bidCost(), bidCost);
			auctioneer.updateBidCost(bidCost);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync startingBid");
		if (startingBid != auctioneer.startingBid()) {
			console.log("  . startingBid updated %s --> %s", auctioneer.startingBid(), startingBid);
			auctioneer.updateStartingBid(startingBid);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync privateAuctionRequirement");
		if (privateAuctionRequirement != auctioneer.privateAuctionRequirement()) {
			console.log(
				"  . privateAuctionRequirement updated %s --> %s",
				auctioneer.privateAuctionRequirement(),
				privateAuctionRequirement
			);
			auctioneer.updatePrivateAuctionRequirement(privateAuctionRequirement);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync earlyHarvestTax");
		if (earlyHarvestTax != auctioneerEmissions.earlyHarvestTax()) {
			console.log("  . earlyHarvestTax updated %s --> %s", auctioneerEmissions.earlyHarvestTax(), earlyHarvestTax);
			auctioneerEmissions.updateEarlyHarvestTax(earlyHarvestTax);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync emissionTaxDuration");
		if (emissionTaxDuration != auctioneerEmissions.emissionTaxDuration()) {
			console.log(
				"  . emissionTaxDuration updated %s --> %s",
				auctioneerEmissions.emissionTaxDuration(),
				emissionTaxDuration
			);
			auctioneerEmissions.updateEmissionTaxDuration(emissionTaxDuration);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync treasurySplit");
		if (treasurySplit != auctioneer.treasurySplit()) {
			console.log("  . treasurySplit updated %s --> %s", auctioneer.treasurySplit(), treasurySplit);
			auctioneer.updateTreasurySplit(treasurySplit);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync treasury");
		if (treasury != auctioneer.treasury()) {
			console.log("  . treasury updated %s --> %s", auctioneer.treasury(), treasury);
			auctioneer.updateTreasury(treasury);
		} else {
			console.log("  . skipped");
		}
	}

	function claimYieldAll(address _recipient) public broadcast loadChain loadContracts loadConfigValues {
		if (!isBlast) revert NotBlastChain();

		uint256 amountWETH = IERC20Rebasing(address(WETH)).getClaimableAmount(address(auctioneer));
		uint256 amountUSDB = IERC20Rebasing(address(USD)).getClaimableAmount(address(auctioneer));
		auctioneer.claimYieldAll(_recipient, amountWETH, amountUSDB, 0);

		amountWETH = IERC20Rebasing(address(WETH)).getClaimableAmount(address(auctioneerFarm));
		amountUSDB = IERC20Rebasing(address(USD)).getClaimableAmount(address(auctioneerFarm));
		auctioneerFarm.claimYieldAll(_recipient, amountWETH, amountUSDB, 0);
	}
}
