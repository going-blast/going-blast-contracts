// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Pausable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

interface IWETH is IERC20 {
	function withdraw(uint256 amount) external;
	function deposit() external payable;
}

contract WETH9 is ERC20, ERC20Burnable, ERC20Pausable, Ownable {
	constructor() ERC20("Wrapped Ether", "WETH") Ownable(msg.sender) {}

	event Deposit(address indexed dst, uint256 amount);
	event Withdrawal(address indexed src, uint256 amount);

	function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}

	function mint(address to, uint256 amount) external onlyOwner {
		_mint(to, amount);
	}

	function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
		super._update(from, to, value);
	}

	function deposit() public payable {
		_mint(msg.sender, msg.value);
		emit Deposit(msg.sender, msg.value);
	}

	function withdraw(uint256 amount) public {
		require(balanceOf(msg.sender) >= amount);
		_burn(msg.sender, amount);
		payable(msg.sender).transfer(amount);
		emit Withdrawal(msg.sender, amount);
	}
}
