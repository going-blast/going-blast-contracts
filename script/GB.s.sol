// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable no-console

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BasicERC20 } from "../src/BasicERC20.sol";
import { GBScriptUtils } from "./GBScriptUtils.sol";
import { BasicERC20 } from "../src/BasicERC20.sol";
import { IWETH, WETH9 } from "../src/WETH9.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { AuctioneerAuction } from "../src/AuctioneerAuction.sol";
import { AuctioneerUser } from "../src/AuctioneerUser.sol";
import { AuctioneerEmissions } from "../src/AuctioneerEmissions.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { GoToken } from "../src/GoToken.sol";
import { VoucherToken } from "../src/VoucherToken.sol";
import { IERC20Rebasing } from "../src/BlastYield.sol";
import { GBMath, AuctionParamsUtils } from "../src/AuctionUtils.sol";
import { AuctionParams, EpochData, PaymentType, BidOptions } from "../src/IAuctioneer.sol";

contract GBScripts is GBScriptUtils {
	using SafeERC20 for IERC20;
	using GBMath for uint256;
	using AuctionParamsUtils for AuctionParams;
	error AlreadyInitialized();
	error NotBlastChain();
	error OnlyAnvil();

	function fullDeploy() public broadcast loadChain loadConfigValues {
		_ANVIL_setupTokens();
		_deployCore();
		_updateTreasury();
		_initializeAuctioneerEmissions();
		_freezeContracts();
		_ANVIL_initArch();
		_ANVIL_initializeAuctioneerFarmEmissions();
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

	function _ANVIL_setupTokens() internal {
		if (isAnvil) {
			// Anvil resets contracts frozen
			writeBool(configPath("contractsFrozen"), false);

			USD = IERC20(address(new BasicERC20("USD", "USD")));
			writeContractAddress("USD", address(USD));
			WETH = IWETH(address(new WETH9()));
			writeContractAddress("WETH", address(WETH));
		} else {
			USD = IERC20(readAddress(contractPath("USD")));
			WETH = IWETH(readAddress(contractPath("WETH")));
		}
	}

	function _ANVIL_initArch() internal {
		if (!isAnvil) return;

		address arch = 0x3a7679E3662bC7c2EB2B1E71FA221dA430c6f64B;
		BasicERC20(address(USD)).mint(arch, 1000e18);
		VOUCHER.mint(arch, 100e18);
		GO.transfer(arch, 100e18);
		arch.call{ value: 1e18 }("");
	}

	function _ANVIL_initializeAuctioneerFarmEmissions() internal {
		if (!isAnvil) return;

		// GO
		uint256 farmGOEmissions = uint256(1000000e18).scaleByBP(500);
		IERC20(GO).safeTransfer(address(auctioneerFarm), farmGOEmissions);
		auctioneerFarm.initializeEmissions(farmGOEmissions, 180 days);
		console.log("AuctioneerFarm GO emissions", GO.balanceOf(address(auctioneerFarm)));

		// VOUCHER
		VOUCHER.mint(address(auctioneerFarm), 100e18 * 180);
		auctioneerFarm.setVoucherEmissions(100e18 * 180, 180 days);
		console.log("AuctioneerFarm VOUCHER emissions", VOUCHER.balanceOf(address(auctioneerFarm)));
	}

	function _deployCore() internal {
		// TODO: check if deployed bytecode matches potentially deploying bytecode?

		GO = new GoToken();
		writeContractAddress("GO", address(GO));

		VOUCHER = new VoucherToken();
		writeContractAddress("VOUCHER", address(VOUCHER));

		auctioneer = new Auctioneer(GO, VOUCHER, USD, WETH);
		writeContractAddress("Auctioneer", address(auctioneer));

		auctioneerAuction = new AuctioneerAuction(USD, WETH, bidCost, bidIncrement, startingBid, privateAuctionRequirement);
		writeContractAddress("AuctioneerAuction", address(auctioneerAuction));

		auctioneerUser = new AuctioneerUser(USD);
		writeContractAddress("AuctioneerUser", address(auctioneerUser));

		auctioneerEmissions = new AuctioneerEmissions(GO);
		writeContractAddress("AuctioneerEmissions", address(auctioneerEmissions));

		auctioneer.link(address(auctioneerUser), address(auctioneerEmissions), address(auctioneerAuction));

		auctioneerFarm = new AuctioneerFarm(USD, GO, VOUCHER);
		writeContractAddress("AuctioneerFarm", address(auctioneerFarm));

		auctioneer.updateFarm(address(auctioneerFarm));

		if (isBlast) {
			auctioneer.initializeBlast();
			auctioneerFarm.initializeBlast(address(WETH));
			auctioneerAuction.initializeBlast();
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

		console.log("AuctioneerEmissions GO amount", GO.balanceOf(address(auctioneerEmissions)));

		uint256 unlockTimestamp = block.timestamp;
		auctioneerEmissions.initializeEmissions(unlockTimestamp);

		EpochData memory currentEpochData = auctioneerEmissions.getEpochDataAtTimestamp(block.timestamp);
		console.log("Epoch", currentEpochData.epoch);
		console.log("EmissionsRemaining", currentEpochData.emissionsRemaining);
		console.log("DaysRemaining", currentEpochData.daysRemaining);
		console.log("Daily emission set", currentEpochData.dailyEmission);
	}

	function _freezeContracts() internal {
		// This must be manually undone, will prevent contracts being overwritten
		writeFreezeContracts();
	}

	function treasuryApproveAuctioneerAuction() public broadcastTreasury loadChain loadContracts {
		WETH.approve(address(auctioneerAuction), UINT256_MAX);
	}
	function ANVIL_treasuryWrapETH() public broadcastTreasury loadChain loadContracts {
		WETH.deposit{ value: 5e18 }();
	}

	function createAuctions() public broadcast loadChain loadContracts loadConfigValues {
		uint256 lotCount = auctioneerAuction.lotCount();
		uint256 jsonAuctionCount = readAuctionCount();

		console.log("Auction readiness checks:");
		console.log("    AuctioneerEmissions initialized", auctioneerEmissions.emissionsInitialized());
		console.log("    Auctioneer treasury:", auctioneer.treasury(), treasury);
		console.log("    WETH address", address(WETH));
		console.log("    Treasury ETH balance:", treasury.balance);
		console.log("    Treasury WETH balance:", WETH.balanceOf(treasury));
		console.log("    Treasury WETH allowance:", WETH.allowance(treasury, address(auctioneer)));

		AuctionParams[] memory params = new AuctionParams[](1);
		console.log("Number of auctions to add: %s", jsonAuctionCount - lotCount);

		for (uint256 i = lotCount; i < jsonAuctionCount; i++) {
			params[0] = readAuction(i);
			console.log("    Deploying auction: LOT # %s", params[0].name);
			console.log("    Lot checks");
			console.log(
				"        Unlock in future %s, block %s auction %s",
				block.timestamp < params[0].unlockTimestamp,
				block.timestamp,
				params[0].unlockTimestamp
			);
			console.log(
				"        WETH less than treasury allowance",
				params[0].tokens[0].amount < WETH.allowance(treasury, address(auctioneer))
			);
			console.log("        WETH less than treasury balance", params[0].tokens[0].amount < WETH.balanceOf(treasury));

			params[0].validate();

			auctioneer.createAuctions(params);
		}

		// TODO: read daily auctions from JSON, create them
		// TODO: mark the daily auctions as created in the JSON file
	}

	function cancelAuction(uint256 lot) public broadcast loadChain loadContracts {
		auctioneer.cancelAuction(lot, false);
	}

	function syncConfigValues() public broadcast loadChain loadContracts loadConfigValues {
		console.log(". sync bidCost");
		if (bidCost != auctioneerAuction.bidCost()) {
			console.log("  . bidCost updated %s --> %s", auctioneerAuction.bidCost(), bidCost);
			auctioneerAuction.updateBidCost(bidCost);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync startingBid");
		if (startingBid != auctioneerAuction.startingBid()) {
			console.log("  . startingBid updated %s --> %s", auctioneerAuction.startingBid(), startingBid);
			auctioneerAuction.updateStartingBid(startingBid);
		} else {
			console.log("  . skipped");
		}

		console.log(". sync privateAuctionRequirement");
		if (privateAuctionRequirement != auctioneerAuction.privateAuctionRequirement()) {
			console.log(
				"  . privateAuctionRequirement updated %s --> %s",
				auctioneerAuction.privateAuctionRequirement(),
				privateAuctionRequirement
			);
			auctioneerAuction.updatePrivateAuctionRequirement(privateAuctionRequirement);
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
		if (treasurySplit != auctioneerAuction.treasurySplit()) {
			console.log("  . treasurySplit updated %s --> %s", auctioneerAuction.treasurySplit(), treasurySplit);
			auctioneerAuction.updateTreasurySplit(treasurySplit);
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

	function ANVIL_bid(
		uint32 userIndex,
		uint256 lot,
		uint8 rune,
		string memory message
	) public loadChain loadContracts loadConfigValues {
		if (!isAnvil) revert OnlyAnvil();

		string memory mnemonic = vm.envString("MNEMONIC");
		(address user, ) = deriveRememberKey(mnemonic, userIndex);
		(address deployer, ) = deriveRememberKey(mnemonic, 0);

		if (USD.balanceOf(user) == 0) {
			vm.broadcast(deployer);
			BasicERC20(address(USD)).mint(user, 10000e18);
		}

		if (user.balance == 0) {
			vm.broadcast(deployer);
			user.call{ value: 1 ether }("");
		}

		if (USD.allowance(user, address(auctioneer)) == 0) {
			vm.broadcast(user);
			USD.approve(address(auctioneer), UINT256_MAX);
		}

		if (block.timestamp < auctioneerAuction.getAuction(lot).unlockTimestamp) return;

		vm.broadcast(user);
		auctioneer.bid(lot, BidOptions({ multibid: 1, rune: rune, paymentType: PaymentType.WALLET, message: message }));
	}
}
