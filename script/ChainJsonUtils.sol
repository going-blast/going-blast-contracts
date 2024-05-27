// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { AuctionParams } from "../src/IAuctioneer.sol";

contract ChainJsonUtils is Script {
	using stdJson for string;

	string public chainName;
	string public deploymentPath;
	string public deploymentJson;
	string public auctionsPath;
	string public auctionsJson;

	error ChainNameNotSet();
	error MissingPath();
	error MissingContractName();
	error DeployedContractWhileFrozen();

	modifier loadChain() {
		chainName = vm.envString("CHAIN_NAME");
		string memory root = vm.projectRoot();
		deploymentPath = string.concat(root, "/data/", chainName, "/deployment.json");
		deploymentJson = vm.readFile(deploymentPath);
		auctionsPath = string.concat(root, "/data/", chainName, "/auctions.json");
		auctionsJson = vm.readFile(auctionsPath);
		_;
	}

	// Paths

	function firstBlockPath() internal pure returns (string memory) {
		return ".firstBlock";
	}
	function contractPath(string memory item) internal pure returns (string memory) {
		return string.concat(".contracts.", item);
	}
	function configPath(string memory item) internal pure returns (string memory) {
		return string.concat(".config.", item);
	}
	function auctioneerConfigPath(string memory item) internal pure returns (string memory) {
		return string.concat(".auctioneerConfig.", item);
	}
	function tokensPath(string memory item) internal pure returns (string memory) {
		return string.concat(".tokens.", item);
	}

	// Primitives

	function readAddress(string memory path) internal view returns (address) {
		if (bytes(path).length == 0) revert MissingPath();
		bytes memory addressRaw = deploymentJson.parseRaw(path);
		return abi.decode(addressRaw, (address));
	}
	function readUint(string memory path) internal view returns (uint256) {
		if (bytes(path).length == 0) revert MissingPath();
		bytes memory uintRaw = deploymentJson.parseRaw(path);
		return abi.decode(uintRaw, (uint256));
	}
	function readBool(string memory path) internal view returns (bool) {
		if (bytes(path).length == 0) revert MissingPath();
		bytes memory boolRaw = deploymentJson.parseRaw(path);
		return abi.decode(boolRaw, (bool));
	}
	function writeAddress(string memory path, address value) internal {
		if (bytes(path).length == 0) revert MissingPath();
		vm.writeJson(vm.toString(value), deploymentPath, path);
	}
	function writeUint(string memory path, uint256 value) internal {
		if (bytes(path).length == 0) revert MissingPath();
		vm.writeJson(vm.toString(value), deploymentPath, path);
	}
	function writeBool(string memory path, bool value) internal {
		if (bytes(path).length == 0) revert MissingPath();
		vm.writeJson(vm.toString(value), deploymentPath, path);
	}

	// Contract freezing
	function readContractsFrozen() internal view returns (bool) {
		return readBool(configPath(".contractsFrozen"));
	}
	function writeContractAddress(string memory contractName, address contractAddress) internal {
		if (bytes(contractName).length == 0) revert MissingPath();
		// if (readContractsFrozen()) revert DeployedContractWhileFrozen();
		writeAddress(contractPath(contractName), contractAddress);
	}
	function writeFreezeContracts() internal {
		writeBool(configPath(".contractsFrozen"), true);
	}

	// First Block
	function writeFirstBlock(uint256 blockNumber) internal {
		writeUint(firstBlockPath(), blockNumber);
	}

	// Auctions

	function readAuctionCount() internal view returns (uint256) {
		return vm.parseJsonKeys(auctionsJson, "$").length;
	}

	function readAuction(uint256 lot) internal view returns (AuctionParams memory params) {
		bytes memory paramsRaw = auctionsJson.parseRaw(string.concat(".", vm.toString(lot)));
		return abi.decode(paramsRaw, (AuctionParams));
	}
}
