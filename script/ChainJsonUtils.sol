// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

contract ChainJsonUtils is Script {
	using stdJson for string;

	string public chainName;
	string public deploymentPath;
	string public deploymentJson;
	string public auctionsPath;
	string public auctionsJson;

	error ChainNameNotSet();
	error MissingPath();

	modifier loadChain() {
		chainName = vm.envString("CHAIN_NAME");
		string memory root = vm.projectRoot();
		deploymentPath = string.concat(root, "/data/", chainName, "/deployment.json");
		deploymentJson = vm.readFile(deploymentPath);
		auctionsPath = string.concat(root, "/data/", chainName, "/auctions.json");
		auctionsJson = vm.readFile(auctionsPath);
		_;
	}

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

	function contractPath(string memory item) internal pure returns (string memory) {
		return string.concat(".contracts.", item);
	}
	function configPath(string memory item) internal pure returns (string memory) {
		return string.concat(".config.", item);
	}
	function auctioneerConfigPath(string memory item) internal pure returns (string memory) {
		return string.concat(".auctioneerConfig.", item);
	}
}
