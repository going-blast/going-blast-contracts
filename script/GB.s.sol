// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable no-console

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBScriptUtils } from "./GBScriptUtils.sol";
import { IWETH, WETH9 } from "../src/WETH9.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { AuctioneerAuction } from "../src/AuctioneerAuction.sol";
import { AuctioneerEmissions } from "../src/AuctioneerEmissions.sol";
import { AuctioneerFarm } from "../src/AuctioneerFarm.sol";
import { GoToken } from "../src/GoToken.sol";
import { VoucherToken } from "../src/VoucherToken.sol";
import { GBMath, AuctionParamsUtils } from "../src/AuctionUtils.sol";
import { AuctionParams, EpochData, PaymentType } from "../src/IAuctioneer.sol";
import { GoingBlastAirdrop } from "../src/GoingBlastAirdrop.sol";

// ANVIL deployment flow
// 	. Deploy tokens
//  . Distribute GO
// 	. Deploy core
//  . Initialize Auctioneer Emissions (GO)
//  . Initialize Auctioneer Farm Emissions (GO + VOUCHER)

// MAINNET deployment flow
//  . Deploy tokens
//  . Initial GO distribution
// 		. 20% to Presale
// 		. 5% to Presale
// 		. Rest to treasury, waiting for deployment
//  . Deploy core
// 	. Treasury approve VOUCH to airdrop
//  . Manually distribute GO
// 		. 60% to Auctioneer Emissions
// 		. 20% to Presale (Treasury)
// 		. 10% to Auctioneer Farm
// 		. 5% to Initial Liquidity (Treasury)
// 		. 5% to Team Treasury
// 	. After Presale ends
// 		. Treasury approve WETH to auctioneer
// 		. Initialize Auctioneer Emissions
// 		. Initialize Auctioneer Farm Emissions
// 		. Create first auctions
// 		. ./env-subgraph-yaml.sh
// 		. Deploy subgraph
// 		. Update subgraph address in frontend

contract GBScripts is GBScriptUtils {
	using SafeERC20 for IERC20;
	using GBMath for uint256;
	using AuctionParamsUtils for AuctionParams;

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// DEPLOYMENT

	function ANVIL_deploy() public broadcast loadChain loadConfigValues {
		if (!isAnvil) return;

		// tokens
		_deployTokens();
		_setupWETH();

		// core
		_deployCore();
		_updateTreasury();
		_updateTeamTreasury();

		// -- To be done manually on mainnet
		_distributeGO();

		// initialize
		_initializeAuctioneerEmissions();
		_initializeAuctioneerFarmEmissions();

		// -- Local frontend testing setup
		_ANVIL_initArch();
	}

	function deployTokens() public broadcast loadChain loadContracts loadConfigValues {
		_deployTokens();
		_setupWETH();
	}

	function distributeGO() public broadcast loadChain loadContracts loadConfigValues {
		// ONLY ANVIL & TESTNET
		_distributeGO();
	}

	function deployCore() public broadcast loadChain loadContracts loadConfigValues {
		_deployCore();
		_updateTreasury();
		_updateTeamTreasury();
	}

	function initializeCore() public broadcast loadChain loadContracts loadConfigValues {
		_initializeAuctioneerEmissions();
		_initializeAuctioneerFarmEmissions();
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MISC SCRIPTS

	function updateTreasury() public broadcast loadChain loadContracts {
		_updateTreasury();
	}

	function claimYieldAll(address _recipient) public broadcast loadChain loadContracts loadConfigValues {
		if (!isBlast) revert NotBlastChain();

		auctioneer.claimYieldAll(_recipient, 0);
		auctioneerFarm.claimYieldAll(_recipient, 0);
	}

	function muteUser(address _user, bool _muted) public broadcast loadChain loadContracts loadConfigValues {
		auctioneer.muteUser(_user, _muted);
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
			console.log(
				"  . earlyHarvestTax updated %s --> %s",
				auctioneerEmissions.earlyHarvestTax(),
				earlyHarvestTax
			);
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

		console.log(". sync teamTreasurySplit");
		if (teamTreasurySplit != auctioneerAuction.teamTreasurySplit()) {
			console.log(
				"  . teamTreasurySplit updated %s --> %s",
				auctioneerAuction.teamTreasurySplit(),
				teamTreasurySplit
			);
			auctioneerAuction.updateTeamTreasurySplit(teamTreasurySplit);
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

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// DEPLOY - PHASE 1 - TOKENS

	function _deployTokens() internal {
		GO = new GoToken();
		writeContractAddress("GO", address(GO));

		VOUCHER = new VoucherToken();
		writeContractAddress("VOUCHER", address(VOUCHER));
	}

	function _setupWETH() internal {
		if (isAnvil) {
			WETH = IWETH(address(new WETH9()));
			writeContractAddress("WETH", address(WETH));
		} else {
			WETH = IWETH(readAddress(contractPath("WETH")));
		}
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// DEPLOY - PHASE 2 - CORE

	function _deployCore() internal {
		writeFirstBlock(block.number);

		auctioneer = new Auctioneer(multisig, GO, VOUCHER, WETH);
		writeContractAddress("Auctioneer", address(auctioneer));

		auctioneerAuction = new AuctioneerAuction(
			address(auctioneer),
			bidCost,
			bidIncrement,
			startingBid,
			privateAuctionRequirement
		);
		writeContractAddress("AuctioneerAuction", address(auctioneerAuction));

		auctioneerEmissions = new AuctioneerEmissions(address(auctioneer), GO);
		writeContractAddress("AuctioneerEmissions", address(auctioneerEmissions));

		auctioneer.link(address(auctioneerEmissions), address(auctioneerAuction));

		auctioneerFarm = new AuctioneerFarm(address(auctioneer), GO, VOUCHER);
		writeContractAddress("AuctioneerFarm", address(auctioneerFarm));

		auctioneer.updateFarm(address(auctioneerFarm));

		// airdrop = new GoingBlastAirdrop(address(VOUCHER), treasury, 0);
		// writeContractAddress("GoingBlastAirdrop", address(airdrop));

		// INITIALIZE BLAST STUFF
		// if (isBlast) {
		// 	auctioneer.initializeBlast();
		// 	auctioneerFarm.initializeBlast();
		// 	auctioneerAuction.initializeBlast();
		// }
	}

	function _updateTreasury() internal {
		auctioneer.updateTreasury(treasury);
		writeAddress(auctioneerConfigPath("treasury"), treasury);
	}

	function _updateTeamTreasury() internal {
		auctioneer.updateTeamTreasury(teamTreasury);
		writeAddress(auctioneerConfigPath("teamTreasury"), teamTreasury);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// DEPLOY - PHASE 2 - INITIALIZE

	function _initializeAuctioneerEmissions() internal {
		if (auctioneerEmissions.emissionsInitialized()) revert AlreadyInitialized();

		uint256 unlockTimestamp = block.timestamp;
		auctioneerEmissions.initializeEmissions(unlockTimestamp);

		EpochData memory currentEpochData = auctioneerEmissions.getEpochDataAtTimestamp(block.timestamp);
		console.log("Epoch", currentEpochData.epoch);
		console.log("EmissionsRemaining", currentEpochData.emissionsRemaining);
		console.log("DaysRemaining", currentEpochData.daysRemaining);
		console.log("Daily emission set", currentEpochData.dailyEmission);
	}

	function _initializeAuctioneerFarmEmissions() internal {
		uint256 farmGOEmissions = uint256(GO_SUPPLY).scaleByBP(500);
		auctioneerFarm.initializeEmissions(farmGOEmissions, 180 days);

		uint256 farmVOUCHEREmissions = 200e18 * 180;
		VOUCHER.mint(address(auctioneerFarm), farmVOUCHEREmissions);
		auctioneerFarm.setVoucherEmissions(farmVOUCHEREmissions, 180 days);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// AUCTIONS

	function createAuctions() public broadcast loadChain loadContracts loadConfigValues {
		uint256 lotCount = auctioneerAuction.lotCount();
		uint256 jsonAuctionCount = readAuctionCount();

		console.log("Auction readiness checks:");
		console.log("    AuctioneerEmissions initialized", auctioneerEmissions.emissionsInitialized());
		console.log("    Auctioneer treasury:", auctioneer.treasury(), treasury);
		console.log("    Treasury ETH balance:", treasury.balance);

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
			console.log("        ETH less than treasury balance", params[0].tokens[0].amount < treasury.balance);

			params[0].validate();

			auctioneer.createAuctions(params);
		}
	}

	function cancelAuction(uint256 lot) public broadcast loadChain loadContracts {
		auctioneer.cancelAuction(lot);
	}

	function messageAuction(uint256 lot, string memory message) public broadcast loadChain loadContracts {
		auctioneer.messageAuction(lot, message);
	}

	function selectRune(uint256 lot, uint8 rune, string memory message) public broadcast loadChain loadContracts {
		auctioneer.selectRune(lot, rune, message);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// ANVIL UTILS

	function ANVIL_treasuryApproveAuctioneer() public broadcastTreasury loadChain loadContracts loadConfigValues {
		if (!isAnvil) return;
		WETH.deposit{ value: 5e18 }();
		WETH.approve(address(auctioneer), UINT256_MAX);
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

		if (user.balance == 0) {
			vm.broadcast(deployer);
			(bool sent, ) = user.call{ value: 1 ether }("");
			if (!sent) revert ETHTransferFailed();
		}

		if (block.timestamp < auctioneerAuction.getAuction(lot).unlockTimestamp) return;

		vm.broadcast(user);
		auctioneer.bid{ value: bidCost }(lot, rune, message, 1, PaymentType.WALLET);
	}

	function _ANVIL_initArch() internal {
		if (!isAnvil) return;

		address arch = 0x3a7679E3662bC7c2EB2B1E71FA221dA430c6f64B;
		VOUCHER.mint(arch, 100e18);
		GO.transfer(arch, 100e18);
		(bool sent, ) = arch.call{ value: 1e18 }("");
		if (!sent) revert ETHTransferFailed();
	}

	function _distributeGO() internal {
		uint256 proofOfBidEmissions = GO_SUPPLY.scaleByBP(6000);
		IERC20(GO).safeTransfer(address(auctioneerEmissions), proofOfBidEmissions);

		uint256 farmEmissions = GO_SUPPLY.scaleByBP(1000);
		IERC20(GO).safeTransfer(address(auctioneerFarm), farmEmissions);

		// Already in treasury
		// uint256 lbpAmount = GO_SUPPLY.scaleByBP(2000);

		// Already in treasury
		// uint256 initialLiquidityAmount = GO_SUPPLY.scaleByBP(500);
	}
}
