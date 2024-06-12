// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "../src/WETH9.sol";
import { AuctionViewUtils, AuctionMutateUtils } from "../src/AuctionUtils.sol";
import { Auctioneer } from "../src/Auctioneer.sol";
import "../src/IAuctioneer.sol";
import { AuctioneerAuction } from "../src/AuctioneerAuction.sol";

contract AuctioneerHarness is Auctioneer {
	constructor(IERC20 _voucher, IWETH _weth) Auctioneer(_voucher, _weth) {}
}

contract AuctioneerAuctionHarness is AuctioneerAuction {
	using AuctionViewUtils for Auction;
	using AuctionMutateUtils for Auction;

	constructor(address _auctioneer) AuctioneerAuction(_auctioneer) {}

	// AuctionUtils
	function exposed_auction_activeWindow(uint256 _lot) public view returns (uint256) {
		return auctions[_lot].activeWindow();
	}
	function exposed_auction_isBiddingOpen(uint256 _lot) public view returns (bool) {
		return auctions[_lot].isBiddingOpen();
	}
	function exposed_auction_isEnded(uint256 _lot) public view returns (bool) {
		return auctions[_lot].isEnded();
	}
	function exposed_auction_hasRunes(uint256 _lot) public view returns (bool) {
		return auctions[_lot].hasRunes();
	}
}
