// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

contract ChainJsonUtils is Script {
	using stdJson for string;

	string public chainName;
	string public jsonPath;
	string public json;

	error ChainNameNotSet();
	error MissingPath();

	modifier loadChain() {
		chainName = vm.envString("CHAIN_NAME");
		string memory root = vm.projectRoot();
		jsonPath = string.concat(root, "/data/", chainName, ".json");
		json = vm.readFile(jsonPath);
		_;
	}

	function readAddress(string memory path) internal view returns (address) {
		if (bytes(path).length == 0) revert MissingPath();
		bytes memory addressRaw = json.parseRaw(path);
		return abi.decode(addressRaw, (address));
	}
	function readUint(string memory path) internal view returns (uint256) {
		if (bytes(path).length == 0) revert MissingPath();
		bytes memory uintRaw = json.parseRaw(path);
		return abi.decode(uintRaw, (uint256));
	}
	function readBool(string memory path) internal view returns (bool) {
		if (bytes(path).length == 0) revert MissingPath();
		bytes memory boolRaw = json.parseRaw(path);
		return abi.decode(boolRaw, (bool));
	}
	function writeAddress(string memory path, address value) internal {
		if (bytes(path).length == 0) revert MissingPath();
		vm.writeJson(vm.toString(value), jsonPath, path);
	}
	function writeUint(string memory path, uint256 value) internal {
		if (bytes(path).length == 0) revert MissingPath();
		vm.writeJson(vm.toString(value), jsonPath, path);
	}
	function writeBool(string memory path, bool value) internal {
		if (bytes(path).length == 0) revert MissingPath();
		vm.writeJson(vm.toString(value), jsonPath, path);
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
