// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// solhint-disable no-console

import "forge-std/Script.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { GBScriptUtils } from "./GBScriptUtils.sol";
import { IWETH, WETH9 } from "../src/WETH9.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import { AuctioneerAuction } from "../src/AuctioneerAuction.sol";
import { VoucherToken } from "../src/VoucherToken.sol";
import { GBMath, AuctionParamsUtils } from "../src/AuctionUtils.sol";
import { AuctionParams, PaymentType } from "../src/IAuctioneer.sol";
import { GoingBlastAirdrop } from "../src/GoingBlastAirdrop.sol";

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
		_deployVouchToken();
		_setupWETH();

		// core
		_deployCore();
		_updateTreasury();

		// -- Local frontend testing setup
		_ANVIL_initArch();
	}

	function deployTokens() public broadcast loadChain loadContracts loadConfigValues {
		_deployVouchToken();
		_setupWETH();
	}

	function deployCore() public broadcast loadChain loadContracts loadConfigValues {
		_deployCore();
		_updateTreasury();
	}

	function initializeBlast() public broadcast loadChain loadContracts loadConfigValues mockBlastYield {
		auctioneer.initializeBlast();
		auctioneerAuction.initializeBlast();
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
		auctioneerAuction.claimYieldAll(_recipient, 0);
	}

	function muteUser(address _user, bool _muted) public broadcast loadChain loadContracts loadConfigValues {
		auctioneer.muteUser(_user, _muted);
	}

	function syncConfigValues() public broadcast loadChain loadContracts loadConfigValues {
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

	function _deployVouchToken() internal {
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

		auctioneer = new Auctioneer(VOUCHER, WETH);
		writeContractAddress("Auctioneer", address(auctioneer));

		auctioneerAuction = new AuctioneerAuction(address(auctioneer));
		writeContractAddress("AuctioneerAuction", address(auctioneerAuction));

		auctioneer.link(address(auctioneerAuction));
	}

	function _updateTreasury() internal {
		auctioneer.updateTreasury(treasury);
		writeAddress(auctioneerConfigPath("treasury"), treasury);
	}

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// AUCTIONS

	function createAuctions() public broadcast loadChain loadContracts loadConfigValues {
		uint256 lotCount = auctioneerAuction.lotCount();
		uint256 jsonAuctionCount = readAuctionCount();

		console.log("Auction readiness checks:");
		console.log("    Auctioneer treasury set?:", auctioneer.treasury());
		console.log("    Creator ETH balance:", msg.sender.balance);

		AuctionParams memory params;
		console.log("Number of auctions to add: %s", jsonAuctionCount - lotCount);

		for (uint256 i = lotCount; i < jsonAuctionCount; i++) {
			params = readAuction(i);
			console.log("    Deploying auction: LOT # %s", params.name);
			console.log("    Lot checks");
			console.log(
				"        Unlock in future %s, block %s auction %s",
				block.timestamp < params.unlockTimestamp,
				block.timestamp,
				params.unlockTimestamp
			);
			console.log("        ETH less than creator balance", params.tokens[0].amount < msg.sender.balance);

			params.validate();

			auctioneer.createAuction(params);
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

	function ANVIL_creatorApproveAuctioneer() public broadcast loadChain loadContracts loadConfigValues {
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
		(bool sent, ) = arch.call{ value: 1e18 }("");
		if (!sent) revert ETHTransferFailed();
	}
}
