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
		IERC20 _bid,
		IWETH _weth,
		uint256 _bidCost,
		uint256 _bidIncrement,
		uint256 _startingBid,
		uint256 _privateRequirement
	) Auctioneer(_usd, _go, _bid, _weth, _bidCost, _bidIncrement, _startingBid, _privateRequirement) {}

	// AuctionUtils
	function exposed_auction_activeWindow(uint256 _lot) public view validAuctionLot(_lot) returns (uint256) {
		return auctions[_lot].activeWindow();
	}
	function exposed_auction_isBiddingOpen(uint256 _lot) public view validAuctionLot(_lot) returns (bool) {
		return auctions[_lot].isBiddingOpen();
	}
	function exposed_auction_isEnded(uint256 _lot) public view validAuctionLot(_lot) returns (bool) {
		return auctions[_lot].isEnded();
	}

	// Internals
	function exposed_getEmissionForAuction(uint256 _unlockTimestamp, uint256 _bp) public view returns (uint256) {
		return _getEmissionForAuction(_unlockTimestamp, _bp);
	}
	function exposed_getEpochDataAtTimestamp(uint256 _timestamp) public view returns (EpochData memory epochData) {
		return _getEpochDataAtTimestamp(_timestamp);
	}
}
