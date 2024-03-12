// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import { Auctioneer } from "../Auctioneer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "../WETH9.sol";
import { AuctionUtils } from "../AuctionUtils.sol";
import "../IAuctioneer.sol";

contract AuctioneerHarness is Auctioneer {
	using AuctionUtils for Auction;

	constructor(
		IERC20 _usd,
		IERC20 _go,
		IWETH _weth,
		uint256 _bidCost,
		uint256 _bidIncrement,
		uint256 _startingBid,
		uint256 _privateRequirement
	) Auctioneer(_usd, _go, _weth, _bidCost, _bidIncrement, _startingBid, _privateRequirement) {}

	function exposed_auction_activeWindow(uint256 _lot) public view validAuctionLot(_lot) returns (int8) {
		return auctions[_lot].activeWindow();
	}

	function exposed_auction_isBiddingOpen(uint256 _lot) public view validAuctionLot(_lot) returns (bool) {
		return auctions[_lot].isBiddingOpen();
	}
	function exposed_auction_isClosed(uint256 _lot) public view validAuctionLot(_lot) returns (bool) {
		return auctions[_lot].isClosed();
	}
	function exposed_auction_activeWindowClosesAtTimestamp(
		uint256 _lot
	) public view validAuctionLot(_lot) returns (uint256) {
		return auctions[_lot].activeWindowClosesAtTimestamp();
	}
}
