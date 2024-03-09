// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
	function withdraw(uint256 amount) external;
	function deposit() external payable;
}
