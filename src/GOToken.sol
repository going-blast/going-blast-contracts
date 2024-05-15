// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract GoToken is ERC20, Ownable, ERC20Permit {
	constructor() ERC20("Going Blast", "GO") Ownable(msg.sender) ERC20Permit("Going Blast") {
		_mint(msg.sender, 10000000e18);
	}
}
