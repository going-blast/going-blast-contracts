// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { GBMath } from "../src/AuctionUtils.sol";

contract TransformDecTest is Test {
	using GBMath for uint256;

	function setUp() public {}

	function test_transformDec() public {
		assertEq(uint256(1e6).transformDec(6, 18), 1e18, "1e6: 6 -> 18 dec");
		assertEq(uint256(1e6).transformDec(6, 12), 1e12, "1e6: 6 -> 12 dec");
		assertEq(uint256(1e6).transformDec(6, 6), 1e6, "1e6: 6 -> 6 dec");

		assertEq(uint256(1.1125e6).transformDec(6, 18), 1.1125e18, "1.1125e6: 6 -> 18 dec");
		assertEq(uint256(1.1125e6).transformDec(6, 12), 1.1125e12, "1.1125e6: 6 -> 12 dec");
		assertEq(uint256(1.1125e6).transformDec(6, 6), 1.1125e6, "1.1125e6: 6 -> 6 dec");

		assertEq(uint256(1e18).transformDec(18, 6), 1e6, "1e18: 18 -> 6 dec");
		assertEq(uint256(1e18).transformDec(18, 12), 1e12, "1e18: 18 -> 12 dec");
		assertEq(uint256(1e18).transformDec(18, 18), 1e18, "1e18: 18 -> 18 dec");

		assertEq(uint256(1.112533576e18).transformDec(18, 6), 1.112533e6, "1.112533576e18: 18 -> 6 dec");
		assertEq(uint256(1.112533576e18).transformDec(18, 12), 1.112533576e12, "1.112533576e18: 18 -> 12 dec");
		assertEq(uint256(1.112533576e18).transformDec(18, 18), 1.112533576e18, "1.112533576e18: 18 -> 18 dec");

		assertEq(uint256(1.1125e6).transformDec(6, 0), 1, "1.1125e6: 6 -> 0 dec");

		assertEq(uint256(1111111111111111111).transformDec(18, 0), 1, "1111111111111111111 (1.11..e18): 18 -> 0 dec");
	}
}
